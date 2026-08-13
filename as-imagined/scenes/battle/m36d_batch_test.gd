extends Node

# [M36D] Suite for the expansion batch — the particle families and mon tasks
# ported after M36C's core.
#
# The bar here is the same one M36C set: it is not enough that a behavior
# runs, it must reproduce the reference's MOTION. Each test below asserts a
# property that would break if the ported math drifted — direction of travel,
# symmetry of an out-and-back, whether an orbit closes, whether a mon is put
# back — rather than merely that a sprite appeared.

var _pass := 0
var _fail := 0
var _registry: AnimBehaviorRegistry
var _dispatcher: AnimDispatcher


func _ready() -> void:
	AnimData.ensure_loaded()
	_registry = AnimBehaviorRegistry.new()
	AnimBehaviors.register_all(_registry)
	_dispatcher = AnimDispatcher.new(_registry)

	_test_every_template_name_resolves()
	_test_coverage_grew()
	_test_powder_drift()
	_test_vortex_rises_and_circles()
	_test_bite_is_symmetric()
	_test_fist_is_static()
	_test_absorption_orb_travels_to_attacker()
	_test_arc_peaks_midflight()
	_test_slice_lifetime()
	_test_mon_tasks_restore()
	_test_elliptical_closes()
	_test_batch2_projectiles()
	_test_batch2_leech_seed_phases()
	_test_batch2_afterimages()
	_test_batch2_sound_tasks()
	_test_batch2_defensive_wall()
	_test_batch3_mon_tasks_restore()
	_test_batch3_rotation_actually_rotates()
	_test_batch3_teleport_hide_is_temporary()
	_test_visibility_never_leaks()
	_test_batch3_particles()
	_test_batch3_raindrops_clean_up()
	_test_iconic_moves_run()
	_test_batch4_linear_family_shares_one_shape()
	_test_batch4_strike_family()
	_test_batch4_aliased_names_share_one_impl()
	_test_batch4_mon_tasks_restore()
	_test_batch4_handshakes_and_bands()
	_test_batch5_aliases_share_one_impl()
	_test_batch5_multi_spawn_families()
	_test_batch5_timing_shapes()
	_test_batch5_mon_tasks_restore()
	_test_batch5_palette_group()
	_test_batch6_helper_reuse()
	_test_batch6_script_terminated()
	_test_batch6_dig_sequence_never_strands()
	_test_batch6_coverage()
	_test_batch7_pairings_and_signal()
	_test_batch7_faithful_details()
	_test_batch7_closes_the_iconic_tier()
	_test_batch8_visibility_trio()
	_test_batch8_visibility_never_leaks()
	_test_batch8_power_scaled_shake()
	_test_batch8_rock_returns_exactly()
	_test_batch8_platform_shake_restores_capture()
	_test_batch8_fly_ball_accelerates()
	_test_batch8_electric_family()
	_test_batch8_static_and_timing()
	_test_batch8_coverage()
	_test_batch9_closes_the_fly_pair()
	_test_batch9_horn_snaps_back()
	_test_batch9_gust_family_shares_one_orbit()
	_test_batch9_alias_and_two_counters()
	_test_batch9_flicker_and_spiral()
	_test_batch9_droplet_and_deform()
	_test_batch9_coverage()
	_test_batch10_alias_and_flash()
	_test_batch10_orbit_and_flickers()
	_test_batch10_phases()
	_test_batch10_coverage()
	_test_batch11_scale_leak_net()
	_test_batch11_decay_and_drift()
	_test_batch11_rollout_windup()
	_test_batch11_spite_overturns_deferral()
	_test_batch11_coverage()
	_test_batch12_near_aliases()
	_test_batch12_shapes()
	_test_batch12_coverage()
	_test_batch13_deferrals_cleared()
	_test_batch14_rotate_and_travel()
	_test_batch14_shapes()
	_test_falling_feather()
	_test_batch15()
	_test_batch15_deferrals_cleared()
	_test_b16_vice_grip_is_not_guillotine()
	_test_b16_time_of_day_reads_the_system_clock()
	_test_b16_stomp_foot_holds_after_landing()
	_test_b16_bounce_ball_land_reveals_the_attacker()
	_test_b16_weather_ball_up_decelerates()
	_test_b16_whirlwind_line_snaps_back()
	_test_b16_rock_scatter_flies_the_way_it_spawned()
	_test_b16_ghost_status_rises_while_swaying()
	_test_b17_squish_deltas_are_per_frame_not_per_command()
	_test_b17_squish_short_is_a_different_depth_not_just_faster()
	_test_b17_night_shade_clone_doubles_then_shrinks_back()
	_test_b17_brick_break_wall_shakes_only_when_asked()
	_test_b17_razor_wind_tornado_orbits()
	_test_b17_megahorn_mirroring_is_side_asymmetric()
	_test_b17_cross_chop_hand_returns()
	_test_b18_baton_pass_switch_falls_through()
	_test_b18_horizontal_slice_is_distance_bound_not_time_bound()
	_test_b18_horizontal_slice_direction_arg()
	_test_b18_left_right_slice_returns()
	_test_b18_photon_geyser_bails_on_an_invisible_target()
	_test_b18_letter_z_drift_mirrors_by_side()
	_test_b18_letter_z_exits_off_either_edge()
	_test_b18_eye_sparkle_dies_with_its_own_animation()
	_test_b20_glare_divisor_is_pair_max_minus_one()
	_test_b20_glare_spawns_pairs_not_singles()
	_test_b20_destiny_bond_spawns_one_shadow_per_visible_foe()
	_test_b20_destiny_bond_shadows_travel_to_their_own_foe()
	_test_b20_attacker_fade_ends_hidden_and_does_not_restore()
	_test_b20_attacker_fade_respects_its_step_delay()
	_test_b21_snatch_signals_the_script_through_arg_7()
	_test_b21_snatch_runs_all_five_states_and_restores()
	_test_b21_grudge_flames_flip_draw_order()
	_test_b21_grudge_flames_start_spread_around_the_target()
	_test_b21_steel_roller_falls_then_sweeps()
	_test_b21_flippable_slash_flips_axes_independently()
	_test_b22_is_target_same_side_polarity()
	_test_b22_mind_blown_ball_retreats_only_halfway()
	_test_b22_mind_blown_half_step_is_exact()
	_test_b22_centred_electricity_anchors_between_both_targets()
	_test_b22_centred_electricity_size_variants()
	_test_b22_steel_beam_orbs_spawns_fifteen_on_an_interval()
	_test_b23_arg_selector_collapses_partners_in_singles()
	_test_b23_target_side_centre_uses_attacker_side_for_an_ally()
	_test_b23_selected_mon_pos_sits_on_the_selected_battler()
	_test_b23_doubles_translate_travels_to_the_selected_battler()
	_test_b23_lightning_builds_a_lattice_column_above_the_screen()
	_test_b23_progressing_bolt_alternates_its_sweep_direction()
	_test_b24_arg_seven_survives_a_command_boundary()
	_test_b24_sin_timer_actually_advances_a_shared_phase()
	_test_b24_sin_phase_actually_reaches_the_sprites()
	_test_b24_gunk_shot_particles_is_the_sin_wave_alias()
	_test_b24_coin_arg_four_is_a_speed_not_a_duration()
	_test_b24_falling_coin_bounces_twice_with_decay()
	_test_b24_acid_droplet_falls_its_duration_not_its_dead_arg()
	_test_b24_acid_bubble_arcs_above_the_straight_line()
	_test_b24_hydro_cannon_pair()
	_test_b24_gunk_shot_impact_sits_where_it_is_told()
	_test_b24_coverage()
	_test_b25_affine_tables_return_to_identity()
	_test_b25_uproar_distorts_then_restores()
	_test_b25_deep_inhale_shiver_window_is_the_underflow()
	_test_b25_deep_inhale_narrows_and_stretches()
	_test_b25_jagged_note_offset_is_also_its_velocity()
	_test_b25_wavy_notes_cycle_the_rainbow()
	_test_b25_wavy_notes_fly_toward_the_target_and_wave()
	_test_b25_slow_notes_rise_and_mirror_by_arg()
	_test_b25_belly_drum_hand_is_static_and_side_mirrored()
	_test_b25_coverage()
	_test_b26_moon_uses_absolute_screen_coordinates()
	_test_b26_moon_waits_to_be_killed_rather_than_timing_out()
	_test_b26_end_fade_kills_the_moon_only_after_the_whiteout()
	_test_b26_sparkle_creeps_down_and_is_capped()
	_test_b26_alpha_fade_in_alternates_its_two_coefficients()
	_test_b26_attacker_fade_from_invisible_is_the_inverse()
	_test_b26_sky_bird_flies_from_attacker_through_target()
	_test_b26_coverage()
	_test_b27_duplicate_pairs_are_aliases()
	_test_b27_conversion_dies_only_on_the_arg7_signal()
	_test_b27_conversion_blend_signals_only_after_its_ramp()
	_test_b27_tri_attack_flickers_holds_then_launches()
	_test_b27_sharpen_sphere_blink_period_grows()
	_test_b27_stealth_rock_arcs_holds_then_blinks_out()
	_test_b27_breath_puff_drifts_away_from_its_own_side()
	_test_b27_grow_and_shrink_returns_to_identity()
	_test_b27_sucker_punch_slides_and_its_wave_is_inert()
	_test_b27_coverage()
	_test_b28_affine_table_sums_and_the_one_exception()
	_test_b28_grow_tasks_use_the_inverted_scale()
	_test_b28_withdraw_rotates_rather_than_moving()
	_test_b28_rotate_vertically_limits_differ_by_side()
	_test_b28_minimize_shrinks_but_double_team_does_not()
	_test_b28_squish_count_is_a_gate_and_a_multiplier()
	_test_b28_compress_pair_differs_only_in_depth()
	_test_b28_duck_down_hop_mirrors_by_side()
	_test_b28_coverage()
	_test_b29_spit_up_spray_is_elliptical_not_circular()
	_test_b29_swallow_orb_decelerates_and_falls_back()
	_test_b29_bonemerang_comes_back()
	_test_b29_wish_star_enters_from_the_far_side()
	_test_b29_angel_path_is_circular_and_slides_off()
	_test_b29_meteor_star_sweeps_inward_on_both_sides()
	_test_b29_yawn_cloud_drifts_then_blinks_out()
	_test_b29_fade_in_pair_starts_invisible()
	_test_b29_string_wrap_uses_the_target_side_midpoint()
	_test_b29_coverage()
	_test_b30_query_tasks_answer_on_the_right_register()
	_test_b30_query_answers_are_actually_correct()
	_test_b30_movement_waves_count_is_a_gate()
	_test_b30_wring_out_orbits_a_whole_number_of_turns()
	_test_b30_punishment_joins_the_affine_impact_alias_chain()
	_test_b30_foresight_glass_mirrors_by_the_battler_it_sits_on()
	_test_b30_confetti_varies_per_particle()
	_test_b30_coverage()
	_test_b31_helping_hand_clap_uses_screen_coords_and_converges()
	_test_b31_helping_hand_movement_is_partner_relative_in_doubles()
	_test_b31_ingrain_root_never_moves_and_flickers_out()
	_test_b31_lock_on_wrapper_is_not_an_alias()
	_test_b31_wood_hammer_waits_before_it_swings()
	_test_b31_conversion2_inverts_conversions_signal()
	_test_b31_perish_note2_is_never_drawn()
	_test_b31_perish_note_sweeps_from_the_screen_centre()
	_test_b31_partner_slides_move_the_partner_not_the_primary()
	_test_b31_coverage()
	_test_b32_superpower_orb_holds_then_crosses()
	_test_b32_devil_orbit_decays_and_reverses()
	_test_b32_flying_notes_scale_the_two_axes_differently()
	_test_b32_bounce_ball_hides_the_attacker_without_leaking()
	_test_b32_dragon_rush_keys_on_the_targets_side()
	_test_b32_overheat_flame_ellipse_is_three_fifths_tall()
	_test_b32_false_swipe_pair_is_not_an_alias()
	_test_b32_geyser_rise_direction_follows_its_offset_sign()
	_test_b32_coin_shower_ellipse_is_tall_and_narrow()
	_test_b32_coverage()
	_test_b33_thrash_pair_are_different_effects()
	_test_b33_facade_blend_cycles_rather_than_holding()
	_test_b33_shake_partner_scales_with_move_power()
	_test_b33_skull_bash_step_is_fixed_point()
	_test_b33_heat_wave_shoves_the_whole_target_side()
	_test_b33_stockpile_counter_stub_is_bounded()
	_test_b33_coverage()
	_test_b34_torment_cadence_is_not_uniform()
	_test_b34_torment_bubbles_alternate_and_converge()
	_test_b34_barrage_strobes_out_rather_than_fading()
	_test_b34_water_sport_sprays_away_from_the_user()
	_test_b34_brine_rains_through_a_side_dependent_band()
	_test_b34_brine_stops_at_ten_drops()
	_test_b34_ions_fall_across_the_sky_not_on_a_battler()
	_test_b34_smokescreen_lands_down_right_of_the_target()
	_test_b34_odor_sleuth_clones_are_mirror_images()
	_test_b34_odor_sleuth_shrinks_away_after_holding()
	_test_b34_magical_leaf_ramps_into_each_colour_then_cuts()
	_test_b34_coverage()
	_test_b35_mist_ball_ignores_its_spawn_offset()
	_test_b35_sky_drop_spawns_on_target_but_hides_the_attacker()
	_test_b35_will_o_wisp_orbs_drift_away_from_their_source()
	_test_b35_will_o_wisp_fire_spiral_grows()
	_test_b35_knock_off_tail_side_branch_is_not_a_mirror()
	_test_b35_zen_headbutt_offset_is_fixed_and_unmirrored()
	_test_b35_aqua_tail_spawns_on_either_battler()
	_test_b35_present_lands_below_the_target()
	_test_b35_present_heal_particle_drifts_linearly()
	_test_b35_twinkle_follows_its_selector()
	_test_b35_coverage()
	_test_b36_moongeist_and_power_shift_arc_to_the_attacker()
	_test_b36_power_shift_mirrors_only_its_x_destination()
	_test_b36_triple_arrow_aims_at_the_target_centre_exactly()
	_test_b36_glacial_lance_converges_on_the_whole_side()
	_test_b36_surging_strikes_aims_at_the_target()
	_test_b36_elliptical_gust_is_flat()
	_test_b36_smelling_salt_sits_above_its_battler()
	_test_b36_lava_plume_flies_straight_not_in_an_orbit()
	_test_b36_searing_shot_rock_refuses_an_invisible_battler()
	_test_b36_upward_sprite_rises_at_constant_speed()
	_test_b36_query_tasks_answer_on_arg_zero()
	_test_b36_coverage()
	_test_b37_rapid_spin_needs_no_scanline_surface()
	_test_b37_rapid_spin_ends_on_a_threshold_in_either_direction()
	_test_b37_elevation_band_sweeps_upward()
	_test_b37_elevation_offset_is_a_shimmer_not_a_screen_jump()
	_test_b37_elevation_clears_its_band_when_done()
	_test_b37_coverage()
	_test_b38_volt_switch_comes_back()
	_test_b38_volt_switch_side_branches_do_different_work()
	_test_b38_superpower_rock_rises_then_takes_its_heading()
	_test_b38_slide_mon_returns_only_when_asked()
	_test_b38_slide_mon_offset_is_restored_on_abort()
	_test_b38_coverage()
	_test_b39_eruption_crouches_before_it_erupts()
	_test_b39_eruption_jitters_the_attacker_both_ways()
	_test_b39_eruption_rocks_all_launch_upward()
	_test_b39_eruption_gravity_is_quadratic_and_subpixel()
	_test_b39_coverage()
	_test_rev_electric_bolt_segments_vary()
	_test_rev_task_affine_keeps_the_feet_planted()
	_test_rev_electric_mirrors_key_on_the_anchor_battler()

	var total := _pass + _fail
	print("m36d_batch_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


class FakeStage extends RefCounted:
	var layer_node: Control
	var nodes: Dictionary = {}
	func _init() -> void:
		layer_node = Control.new()
		layer_node.size = Vector2(1024, 768)
		# TextureRects with a real texture, because that is what the battle
		# scene actually uses (OpponentSprite0 / PlayerSprite0 are
		# TextureRects) -- a plain Control double silently hid the fact that
		# afterimage cloning needs a texture to copy.
		var placeholder := PlaceholderTexture2D.new()
		placeholder.size = Vector2(64, 64)
		for i in range(4):
			var n := TextureRect.new()
			n.texture = placeholder
			n.size = Vector2(64, 64)
			# Attacker low-left, target high-right: a real singles layout, so
			# direction-of-travel assertions are meaningful.
			n.position = Vector2(150 + i * 250, 450 - i * 120)
			layer_node.add_child(n)
			nodes[i] = n
	func sprite_for(b: int) -> Control: return nodes.get(b, null)
	func mon_for(b: int): return nodes.get(b, null)
	func center_of(b: int) -> Vector2:
		var n: Control = nodes.get(b, null)
		return n.position + n.size * 0.5 if n != null else Vector2.ZERO
	func layer() -> Control: return layer_node
	# The batch-37 scanline surface, recorded so a test can observe it.
	var band: Vector3 = Vector3.ZERO
	func set_background_band(top: float, bottom: float, offset_x: float) -> void:
		band = Vector3(top, bottom, offset_x)
	func clear_background_band() -> void:
		band = Vector3.ZERO
	func background_band() -> Vector3: return band
	func pixel_scale() -> float: return maxf(1.0, layer_node.size.x / 240.0)
	func facing_sign() -> float: return 1.0
	var player_side := true
	func attacker_is_player_side() -> bool: return player_side
	func set_battler_visible(b: int, v: bool) -> void:
		# Really applies it: a no-op here would have silently passed the
		# visibility-leak tests, which are the whole point of this double.
		var n: Control = nodes.get(b, null)
		if n != null:
			n.visible = v
	# Batch 8's platform shake drives the background layer. Seeded to a
	# NON-ZERO offset deliberately, so "restores to zero" and "restores to
	# what it captured" are distinguishable outcomes.
	var scroll := Vector2(37.0, -11.0)
	func background_scroll() -> Vector2: return scroll
	func set_background_scroll(v: Vector2) -> void: scroll = v


func _vm(stage: FakeStage) -> AnimScriptVM:
	var vm := AnimScriptVM.new()
	vm.registry = _registry
	vm.stage = stage
	vm.state = AnimScriptVM.State.RUNNING
	return vm


func _spawn(stage: FakeStage, symbol: String, args: Array,
		template: String) -> Dictionary:
	var vm := _vm(stage)
	for i in range(mini(args.size(), AnimScriptVM.ARG_COUNT)):
		vm.args[i] = int(args[i])
	var ctx := {"template": template,
			"template_data": AnimData.template(template),
			"blend": {"eva": 16, "evb": 0}}
	_registry.get_behavior(symbol).call(vm, ctx)
	var sprites: Array = []
	for child in stage.layer_node.get_children():
		if child is AnimSprite:
			sprites.append(child)
	return {"vm": vm, "sprite": sprites[0] if sprites.size() > 0 else null}


func _test_coverage_grew() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	var playable := int(cov["playable"])
	print("  [M36D] %d/%d playable (%.1f%%)"
			% [playable, ids.size(), 100.0 * playable / maxi(1, ids.size())])
	# M36C ended at 23; batch 1 reached 85; batch 2 reaches ~138. The floor
	# guards against regression rather than expressing ambition.
	_chk("coverage holds at the batches' measured level (%d)" % playable,
			playable >= 195)


func _test_powder_drift() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimMovePowderParticle", [0, 0, 40, 80, 5, 1],
			"gPoisonPowderParticleSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	_chk("powder particle spawns", sp != null)
	if sp == null:
		return
	var vm: AnimScriptVM = r["vm"]
	# Spawns on the TARGET (powder hangs over the victim), not the attacker.
	_chk("powder starts at the target, not the attacker",
			sp.centre.distance_to(stage.center_of(1))
			< sp.centre.distance_to(stage.center_of(0)))
	var y0 := sp.offset.y
	for i in range(10):
		vm._step_behaviors()
	_chk("powder drifts downward over time (%.1f -> %.1f)" % [y0, sp.offset.y],
			sp.offset.y > y0)
	_chk("...and oscillates horizontally", not is_zero_approx(sp.offset.x))
	for i in range(40):
		vm._step_behaviors()
	_chk("powder expires on its duration", vm.visual_count() == 0)


func _test_vortex_rises_and_circles() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimParticleInVortex", [0, 0, 256, 30, 8, 16, 0],
			"gWaterHitSplatSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		_chk("vortex particle spawns", false)
		return
	var vm: AnimScriptVM = r["vm"]
	for i in range(10):
		vm._step_behaviors()
	_chk("vortex particle RISES (y offset negative, got %.1f)" % sp.offset.y,
			sp.offset.y < 0.0)
	var x_at_10 := sp.offset.x
	for i in range(10):
		vm._step_behaviors()
	_chk("...while circling horizontally",
			not is_equal_approx(sp.offset.x, x_at_10))


func _test_bite_is_symmetric() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimBite", [0, 0, 0, 256, 128, 8],
			"gSharpTeethSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		_chk("bite spawns", false)
		return
	var vm: AnimScriptVM = r["vm"]
	for i in range(8):
		vm._step_behaviors()
	var peak := sp.offset
	_chk("bite converges over its first half (%s)" % str(peak),
			not peak.is_equal_approx(Vector2.ZERO))
	for i in range(8):
		vm._step_behaviors()
	_chk("bite retreats symmetrically and ends after 2x half-duration",
			vm.visual_count() == 0)


func _test_fist_is_static() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimBasicFistOrFoot", [0, 0, 8, 0, 0],
			"gFistFootSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		_chk("fist spawns", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var start := sp.centre
	for i in range(5):
		vm._step_behaviors()
	_chk("fist does not move (it is a static impact frame)",
			sp.centre.is_equal_approx(start) and sp.offset.is_equal_approx(
					Vector2.ZERO))
	for i in range(6):
		vm._step_behaviors()
	_chk("fist expires after its duration", vm.visual_count() == 0)


func _test_absorption_orb_travels_to_attacker() -> void:
	# The drain orb runs the OPPOSITE way to every attack particle: from the
	# target back to the attacker. Getting this backwards would look wrong in
	# every draining move, so it is asserted by direction, not just motion.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimAbsorptionOrb", [0, 0, 20, 20],
			"gPowerAbsorptionOrbSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		_chk("absorption orb spawns", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var d_start := sp.centre.distance_to(stage.center_of(0))
	for i in range(15):
		vm._step_behaviors()
	_chk("absorption orb travels toward the ATTACKER (%.0f -> %.0f)"
			% [d_start, sp.centre.distance_to(stage.center_of(0))],
			sp.centre.distance_to(stage.center_of(0)) < d_start)


func _test_arc_peaks_midflight() -> void:
	# An arc must bulge away from the straight line and come back — a half
	# sine over the flight. Compare the midpoint against the chord.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimAbsorptionOrb", [0, 0, 40, 20],
			"gPowerAbsorptionOrbSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		return
	var vm: AnimScriptVM = r["vm"]
	var start := sp.centre
	var finish_pos := stage.center_of(0)
	for i in range(10):
		vm._step_behaviors()
	var chord_mid := start.lerp(finish_pos, 10.0 / 20.0)
	_chk("arc departs from the straight chord at mid-flight (%.1f px)"
			% absf(sp.centre.y - chord_mid.y),
			absf(sp.centre.y - chord_mid.y) > 1.0)


func _test_slice_lifetime() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimCuttingSlice", [0, 0, 0],
			"gCuttingSliceSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		_chk("cutting slice spawns", false)
		return
	var vm: AnimScriptVM = r["vm"]
	for i in range(23):
		vm._step_behaviors()
	_chk("slice is still alive just before its 24-frame budget",
			vm.visual_count() == 1)
	vm._step_behaviors()
	_chk("slice ends at 24 frames (20 motion + 4 hold)",
			vm.visual_count() == 0)


func _test_mon_tasks_restore() -> void:
	for entry in [["AnimTask_SwayMon", [0, 8, 4096, 2, 1]],
			["AnimTask_ScaleMonAndRestore", [16, 16, 10, 1, 0]],
			["AnimTask_TranslateMonElliptical", [1, 12, 8, 1, 3]]]:
		var symbol: String = str(entry[0])
		var stage := FakeStage.new()
		var node: Control = stage.nodes[1]
		var base := node.position
		var base_scale := node.scale
		var vm := _vm(stage)
		var args: Array = entry[1]
		for i in range(args.size()):
			vm.args[i] = int(args[i])
		_registry.get_behavior(symbol).call(vm, {})
		var moved := false
		for i in range(400):
			vm._step_behaviors()
			if not node.position.is_equal_approx(base) \
					or not node.scale.is_equal_approx(base_scale):
				moved = true
			if vm.visual_count() == 0:
				break
		_chk("%s actually displaces the mon" % symbol, moved)
		_chk("%s restores position exactly (%s vs %s)"
				% [symbol, str(node.position), str(base)],
				node.position.is_equal_approx(base))
		_chk("%s restores scale exactly" % symbol,
				node.scale.is_equal_approx(base_scale))
		_chk("%s terminates rather than running forever" % symbol,
				vm.visual_count() == 0)


func _test_elliptical_closes() -> void:
	# The -Cos(...) + height term exists so the orbit starts and ends at the
	# mon's real position instead of snapping. Assert frame 1 is near zero.
	var stage := FakeStage.new()
	var node: Control = stage.nodes[1]
	var base := node.position
	var vm := _vm(stage)
	vm.args[0] = 1
	vm.args[1] = 12
	vm.args[2] = 8
	vm.args[3] = 1
	vm.args[4] = 3
	_registry.get_behavior("AnimTask_TranslateMonElliptical").call(vm, {})
	vm._step_behaviors()
	_chk("elliptical orbit begins at the mon's own position (%.1f px off)"
			% node.position.distance_to(base),
			node.position.distance_to(base) < 30.0)


func _test_batch2_projectiles() -> void:
	# Shadow Ball has three phases and must reach the target by the end --
	# a projectile that stops at the midpoint (its phase-1 resting place)
	# would be a plausible-looking but wrong port.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimShadowBall", [10, 5, 15],
			"gShadowBallSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		_chk("shadow ball spawns", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var atk := stage.center_of(0)
	var tgt := stage.center_of(1)
	_chk("shadow ball starts at the attacker",
			sp.centre.distance_to(atk) < sp.centre.distance_to(tgt))
	for i in range(10):
		vm._step_behaviors()
	var mid := sp.centre
	_chk("...gathers toward the midpoint first (%.0f from atk, %.0f from tgt)"
			% [mid.distance_to(atk), mid.distance_to(tgt)],
			mid.distance_to(atk) > 1.0 and mid.distance_to(tgt) > 1.0)
	for i in range(40):
		vm._step_behaviors()
	_chk("...and completes rather than stalling mid-flight",
			vm.visual_count() == 0)

	# The stinger rotates to face its direction of travel.
	var stage2 := FakeStage.new()
	var r2 := _spawn(stage2, "AnimTranslateStinger", [0, 0, 0, 0, 10],
			"gLinearStingerSpriteTemplate")
	var sp2: AnimSprite = r2["sprite"]
	if sp2 != null:
		_chk("stinger rotates toward its target rather than flying sideways",
				not is_zero_approx(sp2.rotation))


func _test_batch2_leech_seed_phases() -> void:
	# Leech Seed is a three-phase script in ONE behavior: arc, hide, sprout.
	# The hidden phase is the one a naive port drops.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimLeechSeed", [0, 0, 0, 0, 12, 20],
			"gLeechSeedSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		_chk("leech seed spawns", false)
		return
	var vm: AnimScriptVM = r["vm"]
	for i in range(12):
		vm._step_behaviors()
	_chk("leech seed lands and then HIDES before sprouting",
			not sp.visible)
	for i in range(11):
		vm._step_behaviors()
	_chk("...then reappears to sprout", sp.visible)
	for i in range(70):
		vm._step_behaviors()
	_chk("...and finishes after the sprout phase", vm.visual_count() == 0)


func _test_batch2_afterimages() -> void:
	# TraceMonBlended makes real afterimages; it must also clean every one up.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0
	vm.args[1] = 1
	vm.args[2] = 4
	vm.args[3] = 3
	_registry.get_behavior("AnimTask_TraceMonBlended").call(vm, {})
	var peak := 0
	for i in range(40):
		vm._step_behaviors()
		var clones := 0
		for child in stage.layer_node.get_children():
			if child.has_meta("_anim_trace"):
				clones += 1
		peak = maxi(peak, clones)
		if vm.visual_count() == 0:
			break
	_chk("trace task produced afterimages (peak %d)" % peak, peak > 0)
	_chk("...and terminated", vm.visual_count() == 0)
	var leftover := 0
	for child in stage.layer_node.get_children():
		if child.has_meta("_anim_trace") and is_instance_valid(child) \
				and not child.is_queued_for_deletion():
			leftover += 1
	_chk("...leaving no afterimage behind (%d)" % leftover, leftover == 0)


func _test_batch2_sound_tasks() -> void:
	# Sound is deferred, but TIMING is not: single-frame cues must not stall a
	# script, and cry waits must cost their real warm-up frames.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_registry.get_behavior("SoundTask_PlaySE1WithPanning").call(vm, {})
	_chk("a single-frame sound cue costs the script nothing",
			vm.visual_count() == 0)

	var vm2 := _vm(stage)
	_registry.get_behavior("SoundTask_WaitForCry").call(vm2, {})
	_chk("a cry wait does hold the script briefly", vm2.visual_count() == 1)
	vm2._step_behaviors()
	vm2._step_behaviors()
	_chk("...and releases once the (silent) cry is done",
			vm2.visual_count() == 0)


func _test_batch2_defensive_wall() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimDefensiveWall", [0, 0, 0],
			"gReflectSparkleSpriteTemplate")
	var sp: AnimSprite = r["sprite"]
	if sp == null:
		return
	var vm: AnimScriptVM = r["vm"]
	_chk("the wall starts invisible and fades IN", is_zero_approx(
			sp.modulate.a))
	for i in range(13):
		vm._step_behaviors()
	_chk("...reaching full opacity", sp.modulate.a > 0.9)
	for i in range(60):
		vm._step_behaviors()
	_chk("...then fading out and ending", vm.visual_count() == 0)


func _test_batch3_mon_tasks_restore() -> void:
	# Every batch-3 mon task must put the battler back -- position, scale AND
	# rotation this time, since these are the first behaviors to rotate one.
	for entry in [["AnimTask_HorizontalShake", [1, 4, 6]],
			["AnimTask_WindUpLunge", [0, 8, 4, 6, 2, 12, 6]],
			["AnimTask_RotateMonSpriteToSide", [8, 512, 1, 2]],
			["AnimTask_RotateMonToSideAndRestore", [8, 512, 1, 0]],
			["AnimTask_DynamaxGrowth", [1]],
			["AnimTask_BlendMonInAndOut", [1, 31, 8, 1, 2]],
			["AnimShakeMonOrBattlePlatforms", [4, 1, 12, 2, 2]]]:
		var symbol: String = str(entry[0])
		var stage := FakeStage.new()
		var node: Control = stage.nodes[1]
		var base := node.position
		var base_scale := node.scale
		var base_rot := node.rotation
		var vm := _vm(stage)
		var args: Array = entry[1]
		for i in range(args.size()):
			vm.args[i] = int(args[i])
		_registry.get_behavior(symbol).call(vm, {})
		for i in range(600):
			vm._step_behaviors()
			if vm.visual_count() == 0:
				break
		_chk("%s terminates" % symbol, vm.visual_count() == 0)
		_chk("%s restores position" % symbol,
				node.position.is_equal_approx(base))
		_chk("%s restores scale" % symbol,
				node.scale.is_equal_approx(base_scale))
		_chk("%s restores rotation" % symbol,
				is_equal_approx(node.rotation, base_rot))


func _test_batch3_rotation_actually_rotates() -> void:
	# Guard against a "restores perfectly because it never moved" pass.
	var stage := FakeStage.new()
	var node: Control = stage.nodes[1]
	var vm := _vm(stage)
	vm.args[0] = 20
	vm.args[1] = 1024
	vm.args[2] = 1
	vm.args[3] = 2
	_registry.get_behavior("AnimTask_RotateMonSpriteToSide").call(vm, {})
	for i in range(10):
		vm._step_behaviors()
	_chk("rotation task genuinely rotates the mon (%.3f rad)" % node.rotation,
			absf(node.rotation) > 0.01)


func _test_batch3_teleport_hide_is_temporary() -> void:
	# Teleport hides the attacker -- that IS the effect -- but the hide must
	# not outlive the animation. Upstream that is guaranteed by the battle
	# controller re-syncing every sprite's visibility once an animation ends
	# (CopyAllBattleSpritesInvisibilities); this port guarantees it by having
	# the VM undo any hide it made. Without that, one Teleport removes a
	# Pokemon from the screen for the rest of the battle -- the exact class of
	# bug 35 scripts (Feint Attack, Shadow Force, Sky Drop, ...) would trip,
	# because they end with a battler still marked invisible.
	var stage := FakeStage.new()
	var node: Control = stage.nodes[0]
	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_Teleport").call(vm, {})
	for i in range(60):
		vm._step_behaviors()
		if vm.visual_count() == 0:
			break
	_chk("teleport terminates", vm.visual_count() == 0)
	_chk("teleport hides the attacker while it runs", not node.visible)
	_chk("...with its scale restored so the next reveal is clean",
			node.scale.is_equal_approx(Vector2.ONE))
	vm._finish()
	_chk("...and the hide is UNDONE when the animation ends", node.visible)


func _test_visibility_never_leaks() -> void:
	# The general invariant, asserted directly rather than per-behavior: no
	# animation may leave a battler invisible once it is over.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.hide_battler(AnimStage.ANIM_TARGET)
	_chk("a script can hide a battler mid-animation",
			not (stage.nodes[1] as Control).visible)
	vm._finish()
	_chk("...and the VM restores it when the run ends",
			(stage.nodes[1] as Control).visible)

	# And a whole real script that ends mid-hide must leave nothing hidden.
	var stage2 := FakeStage.new()
	if _dispatcher.can_play_move(185):  # Feint Attack: invisible with no show
		var vm2 := _dispatcher.make_vm(185, stage2, 0)
		if vm2 != null:
			var frames := 0
			while vm2.is_running() and frames < 2000:
				vm2.step()
				frames += 1
			var all_visible := true
			for i in range(4):
				if not (stage2.nodes[i] as Control).visible:
					all_visible = false
			_chk("Feint Attack (hides with no matching show) leaves every "
					+ "battler visible afterwards", all_visible)


func _test_batch3_particles() -> void:
	# Roar's noise line is exactly 14 frames at a fixed speed.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimRoarNoiseLine", [0, 0, 0],
			"gHorizontalLungeSpriteTemplate")
	var vm: AnimScriptVM = r["vm"]
	if r["sprite"] != null:
		for i in range(13):
			vm._step_behaviors()
		_chk("roar noise line still alive at 13 frames",
				vm.visual_count() == 1)
		vm._step_behaviors()
		_chk("...and ends at exactly 14", vm.visual_count() == 0)

	# The fire spiral stays INVISIBLE for its initial wait, then appears.
	var stage2 := FakeStage.new()
	var r2 := _spawn(stage2, "AnimFireSpiralOutward", [0, 0, 20, 6],
			"gFlamethrowerFlameSpriteTemplate")
	var sp2: AnimSprite = r2["sprite"]
	var vm2: AnimScriptVM = r2["vm"]
	if sp2 != null:
		_chk("fire spiral starts hidden during its wait", not sp2.visible)
		for i in range(7):
			vm2._step_behaviors()
		_chk("...then becomes visible and spirals", sp2.visible)
		var off1 := sp2.offset
		for i in range(6):
			vm2._step_behaviors()
		_chk("...with a growing radius",
				sp2.offset.length() > off1.length())


func _test_batch3_raindrops_clean_up() -> void:
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[1] = 4
	vm.args[2] = 30
	_registry.get_behavior("AnimTask_CreateRaindrops").call(vm, {})
	var peak := 0
	for i in range(200):
		vm._step_behaviors()
		var live := 0
		for child in stage.layer_node.get_children():
			if child is AnimSprite and not (child as AnimSprite).is_finished():
				live += 1
		peak = maxi(peak, live)
		if vm.visual_count() == 0:
			break
	_chk("raindrops spawned (peak %d)" % peak, peak > 0)
	_chk("rain task terminates and clears its drops",
			vm.visual_count() == 0)


func _test_iconic_moves_run() -> void:
	# End-to-end on iconic moves this batch was meant to unblock.
	var unblocked := 0
	for pair in [[77, "Poison Powder"], [78, "Stun Spore"],
			[79, "Sleep Powder"], [22, "Vine Whip"], [44, "Bite"],
			[52, "Ember"]]:
		var id: int = int(pair[0])
		if not _dispatcher.can_play_move(id):
			continue
		unblocked += 1
		var stage := FakeStage.new()
		var vm := _dispatcher.make_vm(id, stage, 0)
		if vm == null:
			_chk("%s builds a VM" % str(pair[1]), false)
			continue
		var frames := 0
		while vm.is_running() and frames < 2000:
			vm.step()
			frames += 1
		_chk("%s runs to completion (%d frames, state=%d)"
				% [str(pair[1]), frames, vm.state],
				vm.state == AnimScriptVM.State.DONE)
		_chk("%s leaves nothing live" % str(pair[1]), vm.visual_count() == 0)
		for i in range(4):
			var expected := Vector2(150 + i * 250, 450 - i * 120)
			_chk("%s restores battler %d" % [str(pair[1]), i],
					(stage.nodes[i] as Control).position.is_equal_approx(
							expected))
	_chk("the batch unblocked several named iconic moves (%d of 6)"
			% unblocked, unblocked >= 4)




# ── batch 4 helpers: thin wrappers over the suite's own _vm/_spawn ────────
var _b4_last: AnimSprite = null


func _make_vm(stage: FakeStage) -> AnimScriptVM:
	return _vm(stage)


func _step(vm: AnimScriptVM, frames: int) -> void:
	for i in range(frames):
		vm._step_behaviors()


func _run(vm: AnimScriptVM, symbol: String, template: String) -> void:
	var ctx := {"template": template,
			"template_data": AnimData.template(template),
			"blend": {"eva": 16, "evb": 0}}
	var before: Array = []
	var stage_layer: Control = vm.stage.layer()
	for child in stage_layer.get_children():
		before.append(child)
	_registry.get_behavior(symbol).call(vm, ctx)
	_b4_last = null
	for child in stage_layer.get_children():
		if child is AnimSprite and not before.has(child):
			_b4_last = child


func _last_sprite(_stage: FakeStage) -> AnimSprite:
	return _b4_last

# ─── batch 4 ──────────────────────────────────────────────────────────────

# The four behaviors Step 0 found to be literally the same shape upstream:
# set a start, set duration/destination, hand off to StartAnimLinearTranslation
# with a stored destroy-callback. They must all actually ARRIVE, and the two
# whose direction is easy to invert must go the right way.
func _test_batch4_linear_family_shares_one_shape() -> void:
	# PowerAbsorptionOrb travels INTO the attacker -- it is a drain, and this
	# is the one direction in the batch that reads as obviously wrong if
	# reversed.
	var stage := FakeStage.new()
	var vm := _make_vm(stage)
	vm.args[0] = 40
	vm.args[1] = 0
	vm.args[2] = 10
	_run(vm, "AnimPowerAbsorptionOrb", "gCottonGuardSporeTemplate")
	var node := _last_sprite(stage)
	var start_d := node.centre.distance_to(stage.center_of(0)) if node != null \
			else 0.0
	_step(vm, 10)
	var end_d := node.centre.distance_to(stage.center_of(0)) if node != null \
			and is_instance_valid(node) else 0.0
	_chk("the absorption orb travels TOWARD the attacker, not away "
			+ "(%.0f -> %.0f)" % [start_d, end_d], end_d < start_d)

	# RaiseSprite's destination is RELATIVE, unlike the orb's absolute one.
	var s2 := FakeStage.new()
	var vm2 := _make_vm(s2)
	vm2.args[2] = -60   # rise
	vm2.args[3] = 12
	_run(vm2, "AnimRaiseSprite", "gAncientPowerRockSpriteTemplate")
	var n2 := _last_sprite(s2)
	var y0 := n2.centre.y if n2 != null else 0.0
	_step(vm2, 12)
	_chk("a raised sprite ends ABOVE where it started",
			n2 != null and is_instance_valid(n2) and n2.centre.y < y0)

	# AirWaveCrescent mirrors ALL FOUR offsets on the opponent's side -- a
	# single mirror, not a per-axis one.
	var s3 := FakeStage.new()
	s3.player_side = false
	var vm3 := _make_vm(s3)
	vm3.args[0] = 20
	vm3.args[1] = 10
	vm3.args[4] = 8
	_run(vm3, "AnimAirWaveCrescent", "gAirWaveCrescentSpriteTemplate")
	var n3 := _last_sprite(s3)
	_chk("an opponent-side air wave starts mirrored on BOTH axes",
			n3 != null and n3.centre.x < s3.center_of(0).x
			and n3.centre.y < s3.center_of(0).y)

	# FlyingSandCrescent is the odd one out: no duration arg at all, it runs
	# until it leaves the screen, so its life depends on its velocity.
	var s4 := FakeStage.new()
	var vm4 := _make_vm(s4)
	vm4.args[0] = 60
	vm4.args[1] = 2048   # 8 px/frame
	_run(vm4, "AnimFlyingSandCrescent", "gFlyingSandCrescentSpriteTemplate")
	var before := vm4.visual_count()
	_step(vm4, 400)
	_chk("the sand crescent exits the screen and cleans itself up "
			+ "(no duration argument involved)",
			before > 0 and vm4.visual_count() == 0)


func _test_batch4_strike_family() -> void:
	# FistOrFootRandomPos lands INSIDE the battler's own box, never at its
	# exact centre -- the scatter is the whole point of the behavior.
	var offsets: Array = []
	for i in range(12):
		var stage := FakeStage.new()
		var vm := _make_vm(stage)
		vm.args[1] = 4
		vm.args[2] = 0
		_run(vm, "AnimFistOrFootRandomPos", "gFistFootRandomPosSpriteTemplate")
		var node := _last_sprite(stage)
		if node != null:
			offsets.append(node.centre - stage.center_of(0))
	var distinct := {}
	for o in offsets:
		distinct[str(o.round())] = true
	_chk("the fist scatters rather than landing on one fixed point "
			+ "(%d distinct positions in 12 draws)" % distinct.size(),
			distinct.size() > 1)

	# SpinningKickOrPunch SNAPS back to full size and zero rotation before it
	# holds -- if the snap were missing the fist would stay looming.
	#
	# ⚠️ **THIS ASSERTION USED TO READ "the kick shrinks while spinning" AND WAS
	# BACKWARDS** (corrected 2026-08-11 with M36R's own direction fix). An
	# affine table's xScale accumulator is an INVERSE scale, so Mega Punch's
	# -4 makes the fist GROW. Source settles it by name: `gGrowAndShrink`
	# opens (-4,-5) and `gShrinkAndGrow` opens (+4,+5)
	# (battle_anim_effects_2.c:490-504). The old assertion was written from
	# the implementation rather than from source, so it locked the inversion
	# in and passed for years; it is rewritten, not relaxed.
	var s2 := FakeStage.new()
	var vm2 := _make_vm(s2)
	vm2.args[3] = 10
	_run(vm2, "AnimSpinningKickOrPunch", "gMegaPunchKickSpriteTemplate")
	var n2 := _last_sprite(s2)
	var full := n2.scale if n2 != null else Vector2.ONE
	_step(vm2, 6)
	var mid := n2.scale if n2 != null and is_instance_valid(n2) else full
	_chk("the kick shrinks while spinning (SPRITE path: the accumulator is the visual scale)", mid.x < full.x)
	_step(vm2, 8)
	_chk("...then snaps back to full size for the landing hold",
			n2 != null and is_instance_valid(n2)
			and is_equal_approx(n2.scale.x, full.x)
			and is_zero_approx(n2.rotation))

	# SlidingKick travels horizontally with a sine riding on top: the x must
	# advance monotonically while y oscillates around the start.
	var s3 := FakeStage.new()
	var vm3 := _make_vm(s3)
	vm3.args[2] = 60
	vm3.args[3] = 20
	vm3.args[4] = 40
	vm3.args[5] = 12
	_run(vm3, "AnimSlidingKick", "gSlidingKickSpriteTemplate")
	var n3 := _last_sprite(s3)
	var y_start := n3.centre.y if n3 != null else 0.0
	var xs: Array = []
	var y_min := y_start
	var y_max := y_start
	for i in range(18):
		_step(vm3, 1)
		if n3 != null and is_instance_valid(n3):
			xs.append(n3.centre.x)
			y_min = minf(y_min, n3.centre.y)
			y_max = maxf(y_max, n3.centre.y)
	var monotonic := true
	for i in range(1, xs.size()):
		if float(xs[i]) < float(xs[i - 1]):
			monotonic = false
	_chk("the sliding kick advances horizontally without reversing", monotonic)
	_chk("...while the sine genuinely displaces it vertically (%.1f px)"
			% (y_max - y_min), (y_max - y_min) > 1.0)

	# NeedleArmSpike rotates to FACE its own direction of travel -- that is
	# what lets one implementation serve leaves, petals, spikes and jabs.
	var s4 := FakeStage.new()
	var vm4 := _make_vm(s4)
	vm4.args[1] = 1     # travel outward
	vm4.args[2] = 40
	vm4.args[3] = 40
	vm4.args[4] = 10
	_run(vm4, "AnimNeedleArmSpike", "gBattleAnimSpriteTemplate_LeafStorm2")
	var n4 := _last_sprite(s4)
	_chk("the spike rotates to face where it is going",
			n4 != null and not is_zero_approx(n4.rotation))

	# A zero duration destroys immediately upstream -- it must not spawn a
	# sprite that then never moves or expires.
	var s5 := FakeStage.new()
	var vm5 := _make_vm(s5)
	vm5.args[4] = 0
	_run(vm5, "AnimNeedleArmSpike", "gBattleAnimSpriteTemplate_LeafStorm2")
	_chk("a zero-duration spike spawns nothing at all",
			vm5.visual_count() == 0)

	# SlashSlice plays its anim, THEN flickers out. The flicker is the shared
	# False Swipe / Cut ending, and it must actually toggle visibility.
	var s6 := FakeStage.new()
	var vm6 := _make_vm(s6)
	_run(vm6, "AnimSlashSlice", "gSlashSliceSpriteTemplate")
	var n6 := _last_sprite(s6)
	var toggles := 0
	var was := n6.visible if n6 != null else true
	for i in range(80):
		_step(vm6, 1)
		if n6 == null or not is_instance_valid(n6):
			break
		if n6.visible != was:
			toggles += 1
			was = n6.visible
	_chk("the slice flickers out rather than simply vanishing (%d toggles)"
			% toggles, toggles >= 2)
	_chk("...and is gone afterwards", vm6.visual_count() == 0)


# Three pairs are the same function under two names upstream. Registering both
# against one implementation is correct; asserting it stops a later session
# "fixing" the duplication by writing a second, divergent copy.
func _test_batch4_aliased_names_share_one_impl() -> void:
	for pair in [["AnimFang", "AnimWhipHit_WaitEnd"],
			["AnimKnockOffStrike", "SpriteCB_LashOutStrike"]]:
		_chk("%s and %s resolve to one implementation"
				% [str(pair[0]), str(pair[1])],
				_registry.get_behavior(str(pair[0]))
				== _registry.get_behavior(str(pair[1])))

	# Fang is terminated by its own sprite anim ending, not a frame count --
	# so it must not run forever when nothing else stops it.
	var stage := FakeStage.new()
	var vm := _make_vm(stage)
	_run(vm, "AnimFang", "gFangSpriteTemplate")
	_chk("Fang spawns", vm.visual_count() > 0)
	_step(vm, 300)
	_chk("...and ends on its own anim rather than running forever",
			vm.visual_count() == 0)

	# KnockOffStrike sweeps an ARC: it must leave its start point and come
	# back near it, not travel in a straight line.
	var s2 := FakeStage.new()
	var vm2 := _make_vm(s2)
	_run(vm2, "AnimKnockOffStrike", "gKnockOffStrikeSpriteTemplate")
	var n2 := _last_sprite(s2)
	if n2 != null:
		var origin := n2.centre
		var far := 0.0
		for i in range(24):
			_step(vm2, 1)
			if not is_instance_valid(n2):
				break
			far = maxf(far, n2.centre.distance_to(origin))
		_chk("the knock-off strike sweeps an arc away from its start "
				+ "(%.0f px)" % far, far > 1.0)


func _test_batch4_mon_tasks_restore() -> void:
	# MonToSubstitute squashes the mon and then DROPS the doll in -- it must
	# end level again, not part-way through the bounce.
	var stage := FakeStage.new()
	var vm := _make_vm(stage)
	var node: Control = stage.nodes[0]
	var base := node.position
	var base_scale := node.scale
	_run(vm, "AnimTask_MonToSubstitute", "")
	_step(vm, 5)
	_chk("the mon is visibly squashed during the first phase",
			not node.scale.is_equal_approx(base_scale))
	_step(vm, 600)
	_chk("the substitute lands level again",
			node.position.is_equal_approx(base))
	_chk("...and its scale is restored", node.scale.is_equal_approx(base_scale))

	# RolePlaySilhouette clones the target, fades it in, squeezes it out, and
	# must free the clone -- a leaked ghost would sit on the battlefield.
	var s2 := FakeStage.new()
	var vm2 := _make_vm(s2)
	var before_children := (s2.layer() as Control).get_child_count()
	_run(vm2, "AnimTask_RolePlaySilhouette", "")
	_step(vm2, 400)
	_chk("the role-play silhouette frees its clone", vm2.visual_count() == 0)
	_chk("...leaving no extra nodes behind",
			(s2.layer() as Control).get_child_count() <= before_children + 1)

	# AttackerPunchWithTrace lunges out and back. Upstream leaves x2 at 0 at
	# the end of the return leg, so the attacker must finish where it began.
	var s3 := FakeStage.new()
	var vm3 := _make_vm(s3)
	var n3: Control = s3.nodes[0]
	var home := n3.position
	_run(vm3, "AnimTask_AttackerPunchWithTrace", "")
	_step(vm3, 3)
	_chk("the attacker lunges", not n3.position.is_equal_approx(home))
	_step(vm3, 60)
	_chk("...and returns exactly home", n3.position.is_equal_approx(home))

	# SlideOffScreen deliberately does NOT restore -- upstream leaves the mon
	# off-screen. What must hold is that the VM's own end-of-run restore puts
	# it back, the safety net the visibility fix established.
	var s4 := FakeStage.new()
	var vm4 := _make_vm(s4)
	var n4: Control = s4.nodes[0]
	var home4 := n4.position
	vm4.args[1] = 40
	_run(vm4, "AnimTask_SlideOffScreen", "")
	_step(vm4, 200)
	_chk("the slide moves the mon off-screen and stops there",
			not n4.position.is_equal_approx(home4))
	vm4._finish()
	_chk("...and the VM's end-of-run restore is what puts it back",
			n4.position.is_equal_approx(home4))


func _test_batch4_handshakes_and_bands() -> void:
	# ConstrictBinding genuinely WAITS on the script: nothing happens until
	# arg 7 goes to -1. Squeezing immediately would desynchronise it.
	var stage := FakeStage.new()
	var vm := _make_vm(stage)
	vm.args[3] = 2
	_run(vm, "AnimConstrictBinding", "gConstrictBindingSpriteTemplate")
	var node := _last_sprite(stage)
	var rest := node.scale if node != null else Vector2.ONE
	_step(vm, 40)
	_chk("the binding holds still until the script arms it",
			node != null and is_instance_valid(node)
			and node.scale.is_equal_approx(rest))
	vm.args[AnimScriptVM.ARG_RET] = -1
	_step(vm, 4)
	_chk("...then squeezes once armed",
			node != null and is_instance_valid(node)
			and not node.scale.is_equal_approx(rest))
	_step(vm, 400)
	_chk("...and finishes after its squeeze count", vm.visual_count() == 0)

	# GetReturnPowerLevel writes a band into arg 7. The thresholds are
	# reproduced exactly INCLUDING the gap at 60, which upstream's sequential
	# non-else comparisons leave falling through to 0.
	for pair in [[0, 0], [59, 0], [60, 0], [61, 1], [91, 1], [92, 2],
			[200, 2], [201, 3], [255, 3]]:
		var s2 := FakeStage.new()
		var vm2 := _make_vm(s2)
		vm2.friendship = int(pair[0])
		_run(vm2, "AnimTask_GetReturnPowerLevel", "")
		_chk("friendship %d -> band %d" % [int(pair[0]), int(pair[1])],
				vm2.args[AnimScriptVM.ARG_RET] == int(pair[1]))

	# Recycle is a long blend: in, hold, out. It must actually reach full
	# opacity in the middle rather than staying faint throughout.
	var s3 := FakeStage.new()
	var vm3 := _make_vm(s3)
	_run(vm3, "AnimRecycle", "gRecycleSpriteTemplate")
	var n3 := _last_sprite(s3)
	_step(vm3, 64)
	_chk("recycle fades all the way in",
			n3 != null and is_instance_valid(n3) and n3.modulate.a > 0.9)
	_step(vm3, 200)
	_chk("...and back out, cleaning up", vm3.visual_count() == 0)

	# SleepLetterZ rises QUADRATICALLY: the distance covered in its second
	# half must exceed the first, which a linear rise could not produce.
	var s4 := FakeStage.new()
	var vm4 := _make_vm(s4)
	_run(vm4, "AnimSleepLetterZ", "gSleepLetterZSpriteTemplate")
	var n4 := _last_sprite(s4)
	var y0 := n4.centre.y if n4 != null else 0.0
	_step(vm4, 30)
	var y1 := n4.centre.y if n4 != null and is_instance_valid(n4) else y0
	_step(vm4, 30)
	var y2 := n4.centre.y if n4 != null and is_instance_valid(n4) else y1
	_chk("the Z rises", y1 < y0)
	_chk("...and accelerates as it goes, so the rise is quadratic not linear "
			+ "(%.1f then %.1f)" % [y0 - y1, y1 - y2], (y1 - y2) > (y0 - y1))

	# SporeDoubleBattle is a genuine structured no-op here (it only reorders
	# BG priorities upstream, and this port has no per-battler BG rank). It
	# must complete rather than hang, since its whole purpose now is to stop
	# gating the moves that call it.
	var s5 := FakeStage.new()
	var vm5 := _make_vm(s5)
	_run(vm5, "AnimTask_SporeDoubleBattle", "")
	_chk("the spore BG-priority task completes immediately",
			vm5.visual_count() == 0)


# ─── batch 5 ──────────────────────────────────────────────────────────────

# Step 0 found four alias groups. Registering both names against one
# implementation is correct; asserting it stops a later session "fixing" the
# duplication into a second, divergent copy.
func _test_batch5_aliases_share_one_impl() -> void:
	for pair in [["AnimTask_SkillSwap", "AnimTask_HeartSwap"],
			["AnimTask_StockpileDeformMon", "AnimTask_SpitUpDeformMon"],
			["AnimTask_StockpileDeformMon", "AnimTask_SwallowDeformMon"]]:
		_chk("%s and %s resolve to one implementation"
				% [str(pair[0]), str(pair[1])],
				_registry.get_behavior(str(pair[0]))
				== _registry.get_behavior(str(pair[1])))
	# Stretch target/attacker are the same body with a different battler, so
	# they are deliberately NOT the same callable -- asserted so the
	# distinction is not "tidied" away.
	_chk("StretchTargetUp and StretchAttackerUp stay distinct (they differ "
			+ "only in which battler, which is real)",
			_registry.get_behavior("AnimTask_StretchTargetUp")
			!= _registry.get_behavior("AnimTask_StretchAttackerUp"))


# Three behaviors in this batch spawn MORE THAN ONE sprite from a single call.
# Porting any of them as a single sprite would look subtly wrong rather than
# broken, so the counts are asserted directly.
func _test_batch5_multi_spawn_families() -> void:
	# Thunder Wave is two sprites 32px apart -- upstream even bumps the visual
	# task count by hand to account for the second destroy.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_run_b5(vm, "AnimThunderWave", "gThunderWaveSpriteTemplate")
	var sprites := _sprites_of(stage)
	_chk("Thunder Wave spawns TWO sprites, not one (%d)" % sprites.size(),
			sprites.size() == 2)
	if sprites.size() == 2:
		var dx: float = absf((sprites[0] as AnimSprite).centre.x
				- (sprites[1] as AnimSprite).centre.x)
		_chk("...side by side rather than stacked (%.0f px apart)" % dx,
				dx > 1.0)
	_step(vm, 60)
	_chk("...and both expire on their 51-frame life", vm.visual_count() == 0)

	# The electric bolt draws itself DOWNWARD, one segment every two frames.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	_run_b5(vm2, "AnimTask_ElectricBolt", "gElectricBoltSegmentSpriteTemplate")
	_step(vm2, 1)
	var after1 := _sprites_of(s2).size()
	_step(vm2, 11)
	var segs := _sprites_of(s2)
	_chk("the bolt spawns segments progressively, not all at once "
			+ "(%d after 1 frame, %d after 12)" % [after1, segs.size()],
			after1 < segs.size())
	_chk("...five segments in total (%d)" % segs.size(), segs.size() == 5)
	if segs.size() == 5:
		var ys: Array = []
		for sp in segs:
			ys.append((sp as AnimSprite).centre.y)
		ys.sort()
		_chk("...each lower than the last, so the bolt travels down",
				float(ys[0]) < float(ys[4]))

	# Skill Swap sends a stream of orbs, not one.
	var s3 := FakeStage.new()
	var vm3 := _vm(s3)
	_run_b5(vm3, "AnimTask_SkillSwap", "gSkillSwapOrbSpriteTemplate")
	_step(vm3, 90)
	_chk("Skill Swap emits a stream of orbs (%d)" % _sprites_of(s3).size(),
			_sprites_of(s3).size() >= 5)

	# Grudge Flames is six flames in ONE frame, spread around the attacker.
	var s4 := FakeStage.new()
	var vm4 := _vm(s4)
	_run_b5(vm4, "AnimTask_GrudgeFlames", "gGrudgeFlameSpriteTemplate")
	_chk("Grudge Flames spawns six flames at once (%d)"
			% _sprites_of(s4).size(), _sprites_of(s4).size() == 6)
	_step(vm4, 4)
	var xs := {}
	for sp in _sprites_of(s4):
		xs[str(round((sp as AnimSprite).centre.x))] = true
	_chk("...spread around the mon rather than stacked (%d distinct x)"
			% xs.size(), xs.size() > 1)


func _test_batch5_timing_shapes() -> void:
	# LockingJaw's timing is asymmetric and easy to get wrong: it MOVES for
	# `bite` frames, then freezes and counts back down from bite to -hold, so
	# the total is 2*bite + hold, not bite + hold.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[3] = 256
	vm.args[5] = 6   # bite
	vm.args[6] = 4   # hold
	_run_b5(vm, "SpriteCB_LockingJaw", "gSharpTeethSpriteTemplate")
	var node := _b5_last
	_step(vm, 6)
	var frozen := node.centre if node != null and is_instance_valid(node) \
			else Vector2.ZERO
	_step(vm, 3)
	_chk("the jaw FREEZES after biting rather than continuing",
			node != null and is_instance_valid(node)
			and node.centre.is_equal_approx(frozen))
	_step(vm, 20)
	_chk("...and expires on 2*bite + hold, not bite + hold",
			vm.visual_count() == 0)

	# SwordsDanceBlade is the one behavior in this batch that is the canonical
	# linear-translation shape: exactly 32px up over exactly 6 frames.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	_run_b5(vm2, "AnimSwordsDanceBlade", "gSwordsDanceBladeSpriteTemplate")
	var n2 := _b5_last
	var y0 := n2.centre.y if n2 != null else 0.0
	_step(vm2, 200)
	_chk("the blade rises and finishes", vm2.visual_count() == 0)

	# HyperBeamOrb's duration is DISTANCE-dependent, not a fixed count -- that
	# is what makes a volley of them arrive staggered rather than together.
	var lifetimes: Array = []
	for trial in range(6):
		var s3 := FakeStage.new()
		var vm3 := _vm(s3)
		_run_b5(vm3, "AnimHyperBeamOrb", "gHyperBeamOrbSpriteTemplate")
		var frames := 0
		while vm3.visual_count() > 0 and frames < 400:
			vm3._step_behaviors()
			frames += 1
		lifetimes.append(frames)
	var distinct := {}
	for l in lifetimes:
		distinct[str(l)] = true
	_chk("hyper beam orbs do not all live the same number of frames "
			+ "(%d distinct in 6 draws)" % distinct.size(), distinct.size() > 1)

	# The ice cube runs four real phases; it must not collapse to a flash.
	var s4 := FakeStage.new()
	var vm4 := _vm(s4)
	_run_b5(vm4, "AnimTask_FrozenIceCube", "sFrozenIceCubeSpriteTemplate")
	var n4 := _b5_last
	if n4 != null:
		_chk("the ice cube starts fully transparent and fades in",
				is_zero_approx(n4.modulate.a))
		_step(vm4, 10)
		_chk("...reaching full opacity after its 10-frame fade",
				is_instance_valid(n4) and n4.modulate.a > 0.9)
	var total := 0
	while vm4.visual_count() > 0 and total < 400:
		vm4._step_behaviors()
		total += 1
	_chk("...and runs a long multi-phase animation, not a flash (%d frames)"
			% total, total > 60)


func _test_batch5_mon_tasks_restore() -> void:
	# Every task that displaces or rescales a battler must put it back.
	for entry in [["AnimTask_Splash", 1], ["AnimTask_StretchTargetUp", 0],
			["AnimTask_TeeterDanceMovement", 0],
			["AnimTask_StockpileDeformMon", 0]]:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		vm.args[1] = int(entry[1])
		var battler: int = 1 if str(entry[0]) == "AnimTask_StretchTargetUp" \
				else 0
		var node: Control = stage.nodes[battler]
		var home := node.position
		var home_scale := node.scale
		_run_b5(vm, str(entry[0]), "")
		var moved := false
		for i in range(400):
			vm._step_behaviors()
			if not node.position.is_equal_approx(home) \
					or not node.scale.is_equal_approx(home_scale):
				moved = true
			if vm.visual_count() == 0 and i > 2:
				break
		_chk("%s actually moves the mon" % str(entry[0]), moved)
		_chk("%s restores its position" % str(entry[0]),
				node.position.is_equal_approx(home))
		_chk("%s restores its scale" % str(entry[0]),
				node.scale.is_equal_approx(home_scale))

	# Zero hops must destroy immediately rather than running a silent loop.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	vm2.args[1] = 0
	_run_b5(vm2, "AnimTask_Splash", "")
	_chk("Splash with zero hops does nothing at all",
			vm2.visual_count() == 0)


func _test_batch5_palette_group() -> void:
	# FlashingHitSplat does NO palette work despite the name and the company
	# it keeps -- it toggles visibility for 14 frames. Asserted so nobody
	# looks for a palette effect that was never there.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_run_b5(vm, "AnimFlashingHitSplat", "gFlashingHitSplatSpriteTemplate")
	var node := _b5_last
	if node != null:
		var first := node.visible
		_step(vm, 1)
		_chk("the flashing hit splat toggles visibility every frame",
				is_instance_valid(node) and node.visible != first)
	_step(vm, 20)
	_chk("...and is gone after its 14 frames", vm.visual_count() == 0)

	# The exclude-blend must genuinely EXCLUDE. This is the one palette
	# operation in the batch with no faithful equivalent here, so what is
	# asserted is the property that survives the approximation: the named
	# battler is untouched while the others are not.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	vm2.args[0] = 0       # exclude the attacker
	vm2.args[1] = 0
	vm2.args[2] = 0
	vm2.args[3] = 16
	vm2.args[4] = 0x7FFF  # pure white -- the case that used to render NOTHING
	var attacker: Control = s2.nodes[0]
	var other: Control = s2.nodes[1]
	_run_b5(vm2, "AnimTask_BlendBattleAnimPalExclude", "")
	_step(vm2, 40)
	# The blend now REPLACES rather than multiplies, so it lives in a shader
	# material rather than in modulate. Asserted on white specifically: under
	# the old multiply this exact case was the identity and rendered nothing,
	# which is what made 126 of the roster's 777 blend sites invisible.
	_chk("the excluded battler is left untouched by the blend",
			attacker.material == null)
	var om := other.material as ShaderMaterial
	_chk("...while a non-excluded battler is genuinely blended",
			om != null)
	_chk("...a blend toward WHITE is now visible rather than a no-op "
			+ "(the multiply identity that hid 126 sites)",
			om != null and float(om.get_shader_parameter("tint_amount")) > 0.5)

	# The blend PERSISTS during a run (upstream never restores it -- scripts
	# pair two calls to blend back), so the question that matters is whether a
	# real script leaves a battler tinted afterwards. Guarded here because
	# this is the third leak of this class in M36 (visibility, displacement,
	# and now colour), and a permanently lilac Pokemon would be exactly as
	# silent as the first two.
	var s3 := FakeStage.new()
	var vm3 := _dispatcher.make_vm(14, s3, 0)   # Swords Dance blends non-attackers
	if vm3 != null:
		var frames := 0
		while vm3.is_running() and frames < 3000:
			vm3.step()
			frames += 1
		var untinted := true
		for i in range(4):
			if not (s3.nodes[i] as Control).modulate.is_equal_approx(
					Color(1, 1, 1, 1)):
				untinted = false
		_chk("a real blending script leaves no battler tinted afterwards",
				untinted)

	# Coverage floor for the batch as a whole.
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 356 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 356)


# ── batch 5 helpers ──────────────────────────────────────────────────────
var _b5_last: AnimSprite = null


func _run_b5(vm: AnimScriptVM, symbol: String, template: String) -> void:
	var ctx := {"template": template,
			"template_data": AnimData.template(template),
			"blend": {"eva": 16, "evb": 0}}
	var before: Array = []
	var layer: Control = vm.stage.layer()
	for child in layer.get_children():
		before.append(child)
	_registry.get_behavior(symbol).call(vm, ctx)
	_b5_last = null
	for child in layer.get_children():
		if child is AnimSprite and not before.has(child):
			_b5_last = child


func _sprites_of(stage: FakeStage) -> Array:
	var out: Array = []
	for child in stage.layer_node.get_children():
		if child is AnimSprite and is_instance_valid(child):
			out.append(child)
	return out


# ─── batch 6 ──────────────────────────────────────────────────────────────

# Step 0 found three behaviors sharing ONE step function upstream (all are
# `if (TranslateAnimHorizontalArc) DestroyAnimSprite`) and four reducing to the
# linear-translation shape. Asserted so the reuse is not "tidied" into
# divergent copies later.
func _test_batch6_helper_reuse() -> void:
	# The three arc users must actually arc -- leave the straight line between
	# their endpoints at mid-flight, which a linear port would not.
	for entry in [["AnimThrowProjectile", "gBlackBallSpriteTemplate", 5],
			["AnimSludgeProjectile", "gSludgeProjectileSpriteTemplate", -1],
			["AnimDirtPlumeParticle", "gDirtPlumeSpriteTemplate", 4]]:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		vm.args[2] = 40
		vm.args[3] = 0
		vm.args[4] = 20 if int(entry[2]) == 4 else 30
		vm.args[5] = 20 if int(entry[2]) != 4 else 20
		if int(entry[2]) >= 0:
			vm.args[int(entry[2])] = 30
		_run_b5(vm, str(entry[0]), str(entry[1]))
		var node := _b5_last
		if node == null:
			_chk("%s spawns" % str(entry[0]), false)
			continue
		var start := node.centre
		var mids: Array = []
		for i in range(30):
			_step(vm, 1)
			if is_instance_valid(node):
				mids.append(node.centre)
		var departed := false
		if mids.size() >= 4:
			var a: Vector2 = start
			var b: Vector2 = mids[mids.size() - 1]
			var m: Vector2 = mids[mids.size() / 2]
			var chord := a.lerp(b, 0.5)
			departed = m.distance_to(chord) > 0.5
		_chk("%s arcs rather than travelling straight" % str(entry[0]),
				departed)

	# The four linear collapses must simply ARRIVE.
	for entry in [["AnimIceBeamParticle", "gIceBeamInnerCrystalSpriteTemplate"],
			["AnimSolarBeamBigOrb", "gSolarBeamBigOrbSpriteTemplate"],
			["AnimWaterGunDroplet", "gWaterGunDropletSpriteTemplate"]]:
		var s2 := FakeStage.new()
		var vm2 := _vm(s2)
		vm2.args[2] = 12
		vm2.args[4] = 12
		_run_b5(vm2, str(entry[0]), str(entry[1]))
		var before := vm2.visual_count()
		_step(vm2, 40)
		_chk("%s completes its travel and cleans up" % str(entry[0]),
				before > 0 and vm2.visual_count() == 0)

	# The beyond-target particles start OFF-SCREEN behind the attacker, which
	# is what lets them pass through the target rather than stopping on it.
	var s3 := FakeStage.new()
	var vm3 := _vm(s3)
	vm3.args[4] = 40
	_run_b5(vm3, "AnimMoveParticleBeyondTarget",
			"gBlizzardIceCrystalSpriteTemplate")
	var n3 := _b5_last
	if n3 != null:
		var layer: Control = s3.layer()
		var outside := n3.centre.x < 0.0 or n3.centre.x > layer.size.x \
				or n3.centre.y < 0.0 or n3.centre.y > layer.size.y
		_chk("the beyond-target particle starts off-screen, not at the "
				+ "attacker", outside)
	_step(vm3, 600)
	_chk("...and terminates by leaving the screen, with no frame count",
			vm3.visual_count() == 0)


# Two behaviors in this batch are ended by the SCRIPT (arg 7), not by any
# internal counter. Registered uncounted, or waitforvisualfinish would hang.
func _test_batch6_script_terminated() -> void:
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 6
	var before := vm.visual_count()
	_run_b5(vm, "AnimOrbitFast", "gElectricTerrainOrbsTemplate")
	_chk("the fast orbit does not count toward completion "
			+ "(it orbits until the script stops it)",
			vm.visual_count() == before)
	_step(vm, 300)
	_chk("...and is still orbiting after 300 frames",
			vm.visual_count() == before)
	vm.args[AnimScriptVM.ARG_RET] = -1
	_step(vm, 2)
	_chk("...ending only when arg 7 says so",
			not _b5_last.visible or _b5_last.is_finished())

	# AuroraBeamRings reads arg 7 live too, but still ends on its own duration.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	vm2.args[4] = 15
	_run_b5(vm2, "AnimAuroraBeamRings", "gAuroraBeamRingSpriteTemplate")
	_step(vm2, 40)
	_chk("the aurora ring still completes on its own duration",
			vm2.visual_count() == 0)


# THE headline risk of this batch. Dig is a four-call sequence upstream and
# omitting any one call strands the attacker -- shoved off the right edge,
# parked below the screen, or simply invisible. Upstream relies entirely on
# the script being correct; here the VM's own end-of-run restores are the net,
# and this is the test that proves the net works.
func _test_batch6_dig_sequence_never_strands() -> void:
	for omit in range(4):
		var stage := FakeStage.new()
		var vm := _vm(stage)
		var node: Control = stage.nodes[0]
		var home := node.position
		var calls := [["AnimTask_DigDownMovement", 0],
				["AnimTask_DigDownMovement", 1],
				["AnimTask_DigUpMovement", 0],
				["AnimTask_DigUpMovement", 1]]
		for i in range(calls.size()):
			if i == omit:
				continue   # deliberately break the sequence
			vm.args[0] = int(calls[i][1])
			_run_b5(vm, str(calls[i][0]), "")
			_step(vm, 30)
		# Whatever state the broken sequence left, ending the run must undo it.
		vm._finish()
		_chk("Dig with call %d omitted still leaves the mon on-screen" % omit,
				node.position.is_equal_approx(home))
		_chk("...and visible" % [], node.visible)

	# The complete sequence should also land level and visible on its own.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	var n2: Control = s2.nodes[0]
	var home2 := n2.position
	for pair in [["AnimTask_DigDownMovement", 0],
			["AnimTask_DigDownMovement", 1],
			["AnimTask_DigUpMovement", 0], ["AnimTask_DigUpMovement", 1]]:
		vm2.args[0] = int(pair[1])
		_run_b5(vm2, str(pair[0]), "")
		_step(vm2, 30)
	_chk("a COMPLETE Dig sequence returns the mon home by itself",
			n2.position.is_equal_approx(home2))
	_chk("...and visible", n2.visible)

	# SetAllNonAttackersInvisiblity is the same shape: a raw setter with no
	# restore of its own, relying on a paired call the script may never make.
	var s3 := FakeStage.new()
	var vm3 := _vm(s3)
	vm3.args[0] = 1
	_run_b5(vm3, "AnimTask_SetAllNonAttackersInvisiblity", "")
	_chk("hiding non-attackers leaves the attacker alone",
			(s3.nodes[0] as Control).visible)
	_chk("...and genuinely hides the others",
			not (s3.nodes[1] as Control).visible)
	vm3._finish()
	_chk("...and the end-of-run restore un-hides them even with no paired call",
			(s3.nodes[1] as Control).visible)


func _test_batch6_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 401 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 401)
	# The moves this batch was picked to unblock, by name.
	for pair in [[347, "Aeroblast"], [58, "Ice Beam"], [59, "Blizzard"],
			[55, "Water Gun"], [62, "Aurora Beam"], [85, "Thunderbolt"],
			[76, "Solar Beam"], [65, "Drill Peck"], [126, "Fire Blast"],
			[352, "Water Pulse"], [237, "Hidden Power"], [269, "Taunt"],
			[188, "Sludge Bomb"], [90, "Fissure"], [91, "Dig"]]:
		_chk("%s is playable" % str(pair[1]),
				_dispatcher.can_play_move(int(pair[0])))


# ─── batch 7 — closing the iconic tier ────────────────────────────────────

# Step 0 was asked which behaviors mutate a BATTLER, because that is the leak
# class M36 has hit repeatedly. The answer was TWO required pairings. This
# tests both, and — more importantly — that breaking either is still caught.
func _test_batch7_pairings_and_signal() -> void:
	# Pairing 1: AttackerStretchAndDisappear deliberately leaves the attacker
	# HIDDEN for ExtremeSpeedMonReappear to undo.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var node: Control = stage.nodes[0]
	var base_scale := node.scale
	_run_b5(vm, "AnimTask_AttackerStretchAndDisappear", "")
	_step(vm, 12)
	_chk("the stretch restores the attacker's SCALE by itself",
			node.scale.is_equal_approx(base_scale))
	_chk("...but deliberately leaves it hidden for its partner",
			not node.visible)
	_run_b5(vm, "AnimTask_ExtremeSpeedMonReappear", "")
	_step(vm, 40)
	_chk("...and the partner brings it back", node.visible)

	# The same, with the partner NEVER called — the leak case.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	var n2: Control = s2.nodes[0]
	_run_b5(vm2, "AnimTask_AttackerStretchAndDisappear", "")
	_step(vm2, 12)
	vm2._finish()
	_chk("a MISSING reappear still leaves the mon visible, because the VM "
			+ "restores what the script forgot", n2.visible)

	# Pairing 2: VoltTackleOrbSlide drags the attacker ~320px off-screen and
	# never puts it back; VoltTackleAttackerReappear is the restore.
	var s3 := FakeStage.new()
	var vm3 := _vm(s3)
	var n3: Control = s3.nodes[0]
	var home := n3.position
	_run_b5(vm3, "AnimVoltTackleOrbSlide", "gVoltTackleOrbSlideSpriteTemplate")
	_step(vm3, 120)
	_chk("the orb slide drags the attacker far off its mark",
			absf(n3.position.x - home.x) > 50.0)
	_run_b5(vm3, "AnimTask_VoltTackleAttackerReappear", "")
	_step(vm3, 200)
	_chk("...and its partner walks it back to exactly home",
			n3.position.is_equal_approx(home))
	_chk("...leaving it visible", n3.visible)

	# And the broken-pair case for that one too.
	var s4 := FakeStage.new()
	var vm4 := _vm(s4)
	var n4: Control = s4.nodes[0]
	var home4 := n4.position
	_run_b5(vm4, "AnimVoltTackleOrbSlide", "gVoltTackleOrbSlideSpriteTemplate")
	_step(vm4, 120)
	vm4._finish()
	_chk("a MISSING volt-tackle reappear still leaves the mon on its mark",
			n4.position.is_equal_approx(home4))

	# The signal is 0x1000, NOT the -1 sentinel every other waiting behavior
	# in this engine uses. Pinned because that is exactly the sort of detail
	# a port gets wrong silently.
	var s5 := FakeStage.new()
	var vm5 := _vm(s5)
	var n5: Control = s5.nodes[0]
	var before := vm5.visual_count()
	_run_b5(vm5, "AnimTask_SetAttackerInvisibleWaitForSignal", "")
	_chk("the wait does not count toward completion (it would deadlock the "
			+ "script that must release it)", vm5.visual_count() == before)
	_chk("...and hides the attacker", not n5.visible)
	vm5.args[AnimScriptVM.ARG_RET] = -1
	_step(vm5, 5)
	_chk("...and -1 does NOT release it", not n5.visible)
	vm5.args[AnimScriptVM.ARG_RET] = 0x1000
	_step(vm5, 2)
	_chk("...only 0x1000 does", n5.visible)


func _test_batch7_faithful_details() -> void:
	# InvertScreenColor is an INVOLUTION and restores nothing: Thunder relies
	# on calling it an even number of times. A port that always inverted would
	# leave the screen wrong after an odd count.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0x4     # invert the target
	var target: Control = stage.nodes[1]
	_run_b5(vm, "AnimTask_InvertScreenColor", "")
	var m1 := target.material as ShaderMaterial
	_chk("inverting once applies an inversion",
			m1 != null and float(m1.get_shader_parameter("invert")) > 0.5)
	_run_b5(vm, "AnimTask_InvertScreenColor", "")
	_chk("...and inverting again undoes it, because it is an involution",
			m1 != null and float(m1.get_shader_parameter("invert")) < 0.5)

	# ShakeTargetInPattern walks a fixed table, and its VERTICAL mode takes an
	# absolute value so the target only ever bounces DOWNWARD -- a real
	# asymmetry between the two modes.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	var n2: Control = s2.nodes[1]
	var home := n2.position
	vm2.args[0] = 30
	vm2.args[1] = 3
	vm2.args[2] = 1      # vertical
	_run_b5(vm2, "AnimTask_ShakeTargetInPattern", "")
	var went_up := false
	for i in range(30):
		_step(vm2, 1)
		if n2.position.y < home.y - 0.01:
			went_up = true
	_chk("a vertical pattern shake never moves the target UP "
			+ "(the absolute value is real)", not went_up)
	_chk("...and restores it exactly", n2.position.is_equal_approx(home))

	# Frustration's power bands are INVERTED relative to Return's -- 0 is the
	# STRONGEST here, because low friendship means a stronger Frustration.
	for pair in [[0, 0], [30, 0], [31, 1], [100, 1], [101, 2], [200, 2],
			[201, 3], [255, 3]]:
		var s3 := FakeStage.new()
		var vm3 := _vm(s3)
		vm3.friendship = int(pair[0])
		_run_b5(vm3, "AnimTask_GetFrustrationPowerLevel", "")
		_chk("friendship %d -> frustration band %d (0 = strongest)"
				% [int(pair[0]), int(pair[1])],
				vm3.args[AnimScriptVM.ARG_RET] == int(pair[1]))

	# ConfuseRayBallSpiral orbits on an ELLIPSE -- 32 across but only 8 down --
	# and drifts downward. A circular port would look wrong.
	var s4 := FakeStage.new()
	var vm4 := _vm(s4)
	_run_b5(vm4, "AnimConfuseRayBallSpiral",
			"gConfuseRayBallSpiralSpriteTemplate")
	var n4 := _b5_last
	if n4 != null:
		var xs := [n4.centre.x]
		var ys := [n4.centre.y]
		for i in range(20):
			_step(vm4, 1)
			if is_instance_valid(n4):
				xs.append(n4.centre.x); ys.append(n4.centre.y)
		var xr: float = (xs.max() as float) - (xs.min() as float)
		var yr: float = (ys.max() as float) - (ys.min() as float)
		_chk("the spiral is wider than it is tall (%.0f vs %.0f)" % [xr, yr],
				xr > yr)
	_step(vm4, 80)
	_chk("...and ends on its own 61 frames", vm4.visual_count() == 0)


func _test_batch7_closes_the_iconic_tier() -> void:
	for pair in [[87, "Thunder"], [109, "Confuse Ray"], [218, "Frustration"],
			[344, "Volt Tackle"], [349, "Dragon Dance"],
			[245, "Extreme Speed"]]:
		_chk("%s is playable" % str(pair[1]),
				_dispatcher.can_play_move(int(pair[0])))
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 419 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 419)


# ── [M36D batch 8] ────────────────────────────────────────────────────────
#
# This batch was picked by how many BLOCKED moves each behavior appears in
# rather than by move family, so the tests are shaped by failure mode rather
# than by theme. Three of the twelve are raw visibility setters that restore
# NOTHING upstream, which is the leak class this project has now hit four
# times -- so the headline assertion here is that a run ending mid-sequence
# still puts every Pokemon back.


func _test_batch8_visibility_trio() -> void:
	var stage := FakeStage.new()

	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_AllBattlersInvisible").call(vm, {})
	var hidden := 0
	for i in range(4):
		if not stage.nodes[i].visible:
			hidden += 1
	_chk("AllBattlersInvisible hides every battler (%d/4)" % hidden,
			hidden == 4)

	_registry.get_behavior("AnimTask_AllBattlersVisible").call(vm, {})
	var shown := 0
	for i in range(4):
		if stage.nodes[i].visible:
			shown += 1
	_chk("AllBattlersVisible is the paired restore (%d/4)" % shown, shown == 4)

	# The except-pair variant compares SPRITES upstream, not battler ids, so
	# the attacker and target must both survive while the partners go.
	var vm2 := _vm(stage)
	_registry.get_behavior(
			"AnimTask_AllBattlersInvisibleExceptAttackerAndTarget").call(vm2, {})
	_chk("...except-pair keeps the attacker",
			stage.nodes[AnimStage.ANIM_ATTACKER].visible)
	_chk("...and keeps the target",
			stage.nodes[AnimStage.ANIM_TARGET].visible)
	_chk("...and hides the attacker's partner",
			not stage.nodes[AnimStage.ANIM_ATK_PARTNER].visible)
	_chk("...and hides the target's partner",
			not stage.nodes[AnimStage.ANIM_DEF_PARTNER].visible)


func _test_batch8_visibility_never_leaks() -> void:
	# The defect these three could ship: a script that hides everyone and
	# never makes the paired call would strand every Pokemon invisible for
	# the rest of the battle. Nothing upstream prevents that; the VM's
	# tracked setter is the net, so it is asserted directly.
	for symbol in ["AnimTask_AllBattlersInvisible",
			"AnimTask_AllBattlersInvisibleExceptAttackerAndTarget"]:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		_registry.get_behavior(symbol).call(vm, {})
		vm._finish()
		var visible := 0
		for i in range(4):
			if stage.nodes[i].visible:
				visible += 1
		_chk("%s cannot strand a Pokemon hidden (%d/4 back)"
				% [symbol, visible], visible == 4)

	# Same net for Fly, which hides the attacker and relies entirely on a
	# later script step to bring it back.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	_run_b5(vm2, "AnimFlyBallUp", "gFlyBallUpSpriteTemplate")
	_chk("FlyBallUp hides the attacker",
			not stage2.nodes[AnimStage.ANIM_ATTACKER].visible)
	vm2._finish()
	_chk("...and a run that ends before the reveal still restores it",
			stage2.nodes[AnimStage.ANIM_ATTACKER].visible)


func _test_batch8_power_scaled_shake() -> void:
	# Magnitude is source/12 clamped 1..16, then split ASYMMETRICALLY:
	# +ceil(mag/2) one way, -floor(mag/2) the other. An even split would look
	# almost identical on screen and be wrong.
	var stage := FakeStage.new()
	var base: Vector2 = stage.nodes[AnimStage.ANIM_TARGET].position

	var vm := _vm(stage)
	vm.move_power = 100          # -> mag 8, so +4 / -4 (even: symmetric)
	vm.args[0] = 0; vm.args[1] = 0; vm.args[2] = 40
	vm.args[3] = 1; vm.args[4] = 0
	_registry.get_behavior(
			"AnimTask_ShakeTargetBasedOnMovePowerOrDmg").call(vm, {})
	_step(vm, 1)
	var a: float = stage.nodes[AnimStage.ANIM_TARGET].position.x - base.x
	_step(vm, 1)
	var b: float = stage.nodes[AnimStage.ANIM_TARGET].position.x - base.x
	_chk("power 100 shakes the target horizontally", not is_zero_approx(a))
	_chk("...and reverses on the next step", signf(a) != signf(b))

	# Odd magnitude: 90/12 = 7 -> +4 / -3, a genuine lean.
	var stage2 := FakeStage.new()
	var base2: Vector2 = stage2.nodes[AnimStage.ANIM_TARGET].position
	var vm2 := _vm(stage2)
	vm2.move_power = 90
	vm2.args[0] = 0; vm2.args[1] = 0; vm2.args[2] = 40
	vm2.args[3] = 1; vm2.args[4] = 0
	_registry.get_behavior(
			"AnimTask_ShakeTargetBasedOnMovePowerOrDmg").call(vm2, {})
	_step(vm2, 1)
	var up: float = absf(stage2.nodes[AnimStage.ANIM_TARGET].position.x - base2.x)
	_step(vm2, 1)
	var down: float = absf(stage2.nodes[AnimStage.ANIM_TARGET].position.x - base2.x)
	_chk("an odd magnitude leans one way (%.1f vs %.1f)" % [up, down],
			not is_equal_approx(up, down))

	# arg0 switches the source outright. Damage 0 with power 200 must behave
	# as damage-derived (mag 1), not power-derived (mag 16).
	var stage3 := FakeStage.new()
	var base3: Vector2 = stage3.nodes[AnimStage.ANIM_TARGET].position
	var vm3 := _vm(stage3)
	vm3.move_power = 200
	vm3.move_damage = 0
	vm3.args[0] = 1; vm3.args[1] = 0; vm3.args[2] = 40
	vm3.args[3] = 1; vm3.args[4] = 0
	_registry.get_behavior(
			"AnimTask_ShakeTargetBasedOnMovePowerOrDmg").call(vm3, {})
	_step(vm3, 1)
	var dmg_shift: float = absf(
			stage3.nodes[AnimStage.ANIM_TARGET].position.x - base3.x)
	_chk("arg0=1 reads damage, not power (%.1f << %.1f)" % [dmg_shift, up],
			dmg_shift < up)

	# Vertical is written ABSOLUTELY upstream -- it returns to exactly 0 on
	# the off-phase rather than to whatever offset was already there.
	var stage4 := FakeStage.new()
	var node4: Control = stage4.nodes[AnimStage.ANIM_TARGET]
	var base4: Vector2 = node4.position
	var vm4 := _vm(stage4)
	vm4.move_power = 96
	vm4.args[0] = 0; vm4.args[1] = 0; vm4.args[2] = 6
	vm4.args[3] = 0; vm4.args[4] = 1
	_registry.get_behavior(
			"AnimTask_ShakeTargetBasedOnMovePowerOrDmg").call(vm4, {})
	_step(vm4, 1)
	_chk("vertical mode moves the target on the on-phase",
			not is_equal_approx(node4.position.y, base4.y))
	_step(vm4, 1)
	_chk("...and returns to exactly zero on the off-phase",
			is_equal_approx(node4.position.y, base4.y))
	_step(vm4, 20)
	_chk("...and the mon is fully restored at the end",
			node4.position.is_equal_approx(base4))


func _test_batch8_rock_returns_exactly() -> void:
	# The three motion phases are out / back-twice / out, so travel and
	# rotation cancel EXACTLY -- there is no corrective restore doing the work
	# for a drifting port. Asserted on the raw values, not approximately.
	var stage := FakeStage.new()
	var node: Control = stage.nodes[AnimStage.ANIM_ATTACKER]
	var base := node.position
	var base_rot := node.rotation
	var vm := _vm(stage)
	vm.args[0] = AnimStage.ANIM_ATTACKER; vm.args[1] = 2; vm.args[2] = 1
	_registry.get_behavior("AnimTask_RockMonBackAndForth").call(vm, {})

	var moved := false
	var rotated := false
	for i in range(200):
		_step(vm, 1)
		if not node.position.is_equal_approx(base):
			moved = true
		if not is_equal_approx(node.rotation, base_rot):
			rotated = true
		if vm.visual_count() == 0:
			break
	_chk("RockMonBackAndForth actually displaces the mon", moved)
	_chk("...and actually rotates it", rotated)
	_chk("...and ends exactly back on its mark",
			node.position.is_equal_approx(base))
	_chk("...with rotation exactly restored",
			is_equal_approx(node.rotation, base_rot))

	# A count of zero is a real early-out upstream, not an error.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[0] = AnimStage.ANIM_ATTACKER; vm2.args[1] = 0; vm2.args[2] = 1
	_registry.get_behavior("AnimTask_RockMonBackAndForth").call(vm2, {})
	_chk("a rock count of zero runs nothing at all", vm2.visual_count() == 0)

	# Intensity does NOT widen the excursion, which is worth pinning because
	# it is the opposite of what the constants suggest at a glance: the phase
	# shortens (8 - 2i frames) exactly as the step widens (i + 2 px), so the
	# peak travel lands at 16 / 18 / 16 px across the three tiers and is not
	# even monotonic. Total rotation per phase behaves the same way
	# (2048 / 2304 / 2048). What intensity actually controls is SPEED, so
	# that is what is asserted.
	var durations: Array = []
	for intensity in [0, 2]:
		var st := FakeStage.new()
		var v := _vm(st)
		v.args[0] = AnimStage.ANIM_ATTACKER; v.args[1] = 1
		v.args[2] = intensity
		_registry.get_behavior("AnimTask_RockMonBackAndForth").call(v, {})
		var frames := 0
		for i in range(200):
			_step(v, 1)
			frames += 1
			if v.visual_count() == 0:
				break
		durations.append(frames)
	_chk("intensity 2 rocks FASTER than intensity 0 (%d < %d frames)"
			% [durations[1], durations[0]], durations[1] < durations[0])


func _test_batch8_platform_shake_restores_capture() -> void:
	# The background may already be mid-scroll, so the shake must restore the
	# offset it CAPTURED, not zero -- the same rule M36E3's platform shake
	# established. The stage double seeds a non-zero scroll to tell the two
	# apart.
	var stage := FakeStage.new()
	var initial := stage.background_scroll()
	var vm := _vm(stage)
	vm.args[0] = 4; vm.args[1] = 4; vm.args[2] = 6; vm.args[3] = 1
	_registry.get_behavior("AnimTask_ShakeBattlePlatforms").call(vm, {})
	_chk("the shake offsets the background immediately",
			not stage.background_scroll().is_equal_approx(initial))

	var min_y := 0.0
	for i in range(60):
		_step(vm, 1)
		min_y = minf(min_y, stage.background_scroll().y - initial.y)
		if vm.visual_count() == 0:
			break
	_chk("...and restores the CAPTURED offset, not zero",
			stage.background_scroll().is_equal_approx(initial))
	# y alternates between -offset and 0 upstream; it never goes positive.
	_chk("...with the vertical axis only ever going one way (%.1f)" % min_y,
			min_y < 0.0)


func _test_batch8_fly_ball_accelerates() -> void:
	# The ball is not a linear riser: the velocity accumulator grows every
	# frame, so later steps cover more ground than earlier ones. A linear
	# port would pass a naive "does it go up" check and still be wrong.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0; vm.args[1] = 0; vm.args[2] = 5; vm.args[3] = 40
	_run_b5(vm, "AnimFlyBallUp", "gFlyBallUpSpriteTemplate")
	var node := _b5_last
	_chk("FlyBallUp spawns a ball", node != null)
	if node == null:
		return
	var start_y := node.centre.y

	_step(vm, 4)
	_chk("...which holds still through the launch delay",
			is_equal_approx(node.centre.y, start_y))

	# The rise is genuinely slow to start: with accel 40 the 8.8 accumulator
	# needs 7 frames just to reach one whole pixel, which is exactly the
	# quadratic shape being asserted -- a linear port would move on frame 1.
	_step(vm, 12)
	var early := start_y - node.centre.y
	var mid := node.centre.y
	_step(vm, 12)
	var late := mid - node.centre.y
	_chk("...then rises (%.1f px)" % early, early > 0.0)
	_chk("...accelerating rather than travelling linearly (%.1f -> %.1f)"
			% [early, late], late > early)


func _test_batch8_electric_family() -> void:
	# SparkElectricity places x from SINE and y from COSINE of the same index,
	# so index 0 sits directly BELOW the centre. Swapping the two would put it
	# to the right and look plausible while being wrong.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0; vm.args[1] = 20; vm.args[2] = 64; vm.args[3] = 12
	vm.args[4] = AnimStage.ANIM_TARGET
	_run_b5(vm, "AnimSparkElectricity", "gSparkElectricitySpriteTemplate")
	var spark := _b5_last
	_chk("SparkElectricity spawns", spark != null)
	if spark != null:
		var c := stage.center_of(AnimStage.ANIM_TARGET)
		_chk("...at index 0 it sits below the centre, not beside it",
				absf(spark.centre.y - c.y) > absf(spark.centre.x - c.x))
		_chk("...and is rotated by arg 2",
				not is_zero_approx(spark.rotation))
		_step(vm, 11)
		_chk("...and lives its full 12 frames", vm.visual_count() > 0)
		_step(vm, 2)
		_chk("...then dies on schedule", vm.visual_count() == 0)

	# ElectricChargingParticles converges on the battler and SPEEDS UP as it
	# runs, and -- the part that makes it safe to wait on -- only ends once
	# the last particle has landed, not when the last one spawns.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[0] = AnimStage.ANIM_ATTACKER; vm2.args[1] = 8
	vm2.args[2] = 1; vm2.args[3] = 2
	_registry.get_behavior(
			"AnimTask_ElectricChargingParticles").call(vm2, {})
	var seen := 0
	var closing := false
	var prev_far := -1.0
	var centre := stage2.center_of(AnimStage.ANIM_ATTACKER)
	for i in range(40):
		_step(vm2, 1)
		var live := _sprites_of(stage2)
		seen = maxi(seen, live.size())
		if live.size() > 0:
			var d: float = (live[0] as AnimSprite).centre.distance_to(centre)
			if prev_far >= 0.0 and d < prev_far:
				closing = true
			prev_far = d
	_chk("charging particles spawn over time (%d at once)" % seen, seen > 0)
	_chk("...and converge on the battler", closing)
	var still_running := vm2.visual_count() > 0
	var still_live := not _sprites_of(stage2).is_empty()
	_chk("...and the task outlives its last spawn if any are still flying",
			not still_live or still_running)
	_step(vm2, 200)
	_chk("...but does finish", vm2.visual_count() == 0)


func _test_batch8_static_and_timing() -> void:
	# GrowingShockWaveOrb is a contract-then-expand under the INVERTED GBA
	# affine rule: the parameter climbs, so the rendered orb shrinks first.
	# Reading the inversion backwards would produce exactly the opposite
	# motion, which is the whole reason this is asserted on direction.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_run_b5(vm, "AnimGrowingShockWaveOrb",
			"gGrowingShockWaveOrbSpriteTemplate")
	var orb := _b5_last
	_chk("shockwave orb spawns", orb != null)
	if orb != null:
		var s0 := orb.scale.x
		_step(vm, 25)
		var s1 := orb.scale.x
		_step(vm, 30)
		var s2 := orb.scale.x
		_chk("...contracts first (%.2f -> %.2f)" % [s0, s1], s1 < s0)
		_chk("...then expands again (%.2f -> %.2f)" % [s1, s2], s2 > s1)
		_step(vm, 20)
		_chk("...over 60 frames", vm.visual_count() == 0)

	# CrossImpact is a pure timing element: it must NOT move.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[0] = 0; vm2.args[1] = 0
	vm2.args[2] = AnimStage.ANIM_TARGET; vm2.args[3] = 10
	_run_b5(vm2, "AnimCrossImpact", "gCrossImpactSpriteTemplate")
	var cross := _b5_last
	if cross != null:
		var where := cross.centre
		_step(vm2, 8)
		_chk("CrossImpact holds perfectly still", cross.centre.is_equal_approx(where))
		_chk("...for its full duration", vm2.visual_count() > 0)
		_step(vm2, 4)
		_chk("...then goes", vm2.visual_count() == 0)

	# The gust palette rotation is a structured no-op (sprite palettes are not
	# recoverable from composited PNGs) -- but its FRAME COST is the contract
	# a following waitforvisualfinish depends on, so that is what is pinned.
	var stage3 := FakeStage.new()
	var vm3 := _vm(stage3)
	vm3.args[0] = 3; vm3.args[1] = 30
	_registry.get_behavior(
			"AnimTask_AnimateGustTornadoPalette").call(vm3, {})
	_step(vm3, 29)
	_chk("the gust palette task still costs its declared frames",
			vm3.visual_count() > 0)
	_step(vm3, 2)
	_chk("...and releases at its declared lifetime", vm3.visual_count() == 0)


func _test_batch8_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 446 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 446)


# ── [M36D batch 9] ────────────────────────────────────────────────────────
#
# Picked by measured yield across tiers rather than by generation (Rob's
# amendment to Decision 5 after batch 8 measured the two remaining tiers).
# 16 behaviors, 70 moves. Several collapse onto helpers M36C and batches 5-6
# already built, so the tests concentrate on the handful of genuinely
# distinctive shapes -- and on the one real pairing this batch closes.


func _test_batch9_closes_the_fly_pair() -> void:
	# Batch 8 shipped AnimFlyBallUp, which hides the attacker and relies on a
	# later script step to bring it back; until now only the VM's restore net
	# did that. AnimFlyBallAttack IS that step -- upstream assigns arg 1
	# straight into the attacker's `invisible` as the ball leaves. Asserted
	# through the REAL behavior, with the VM still running, so a pass cannot
	# be the safety net doing the work.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_run_b5(vm, "AnimFlyBallUp", "gFlyBallUpSpriteTemplate")
	_chk("Fly: the up-half hides the attacker",
			not stage.nodes[AnimStage.ANIM_ATTACKER].visible)

	vm.args[0] = 8
	vm.args[1] = 0        # 0 = bring the attacker back
	_run_b5(vm, "AnimFlyBallAttack", "gFlyBallAttackSpriteTemplate")
	var ball := _b5_last
	_chk("Fly: the attack-half spawns a ball", ball != null)
	_step(vm, 4)
	_chk("...and the attacker is still hidden mid-flight",
			not stage.nodes[AnimStage.ANIM_ATTACKER].visible)
	_step(vm, 8)
	_chk("...revealed by the real script step, not the VM's net",
			stage.nodes[AnimStage.ANIM_ATTACKER].visible)

	# arg 1 = 1 means "leave it hidden" -- the discriminator that proves the
	# reveal reads the argument rather than being unconditional.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	_run_b5(vm2, "AnimFlyBallUp", "gFlyBallUpSpriteTemplate")
	vm2.args[0] = 6
	vm2.args[1] = 1
	_run_b5(vm2, "AnimFlyBallAttack", "gFlyBallAttackSpriteTemplate")
	_step(vm2, 12)
	_chk("...and arg 1 = 1 deliberately leaves it hidden",
			not stage2.nodes[AnimStage.ANIM_ATTACKER].visible)
	vm2._finish()
	_chk("...with the net still catching that case at run end",
			stage2.nodes[AnimStage.ANIM_ATTACKER].visible)

	_chk("Fly (19) is playable", _dispatcher.can_play_move(19))


func _test_batch9_horn_snaps_back() -> void:
	# The quirk: on the SECOND-TO-LAST frame the horn teleports to its
	# recorded origin and only then dies. A port that merely interpolates
	# toward the destination looks close and never actually lands there.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0; vm.args[1] = 0; vm.args[2] = 10
	_run_b5(vm, "AnimHornHit", "gHornHitSpriteTemplate")
	var horn := _b5_last
	_chk("horn spawns", horn != null)
	if horn == null:
		return
	var target := stage.center_of(AnimStage.ANIM_TARGET)
	var start_d := horn.centre.distance_to(target)
	_chk("...starting off to one side of the target (%.0f px)" % start_d,
			start_d > 1.0)
	_step(vm, 5)
	var mid_d := horn.centre.distance_to(target)
	_chk("...sweeping toward it (%.0f -> %.0f)" % [start_d, mid_d],
			mid_d < start_d)
	# Frame 9 of 10 is the snap.
	_step(vm, 4)
	_chk("...then SNAPPING exactly onto its origin before dying (%.2f px)"
			% horn.centre.distance_to(target),
			horn.centre.distance_to(target) < 0.01)
	_step(vm, 2)
	_chk("...and it is gone on the next frame", vm.visual_count() == 0)


func _test_batch9_gust_family_shares_one_orbit() -> void:
	# EllipticalGust and EllipticalGustCentered share ONE step function
	# upstream and differ only in placement. Both must therefore trace the
	# same shape -- and that shape is an ELLIPSE, 32 across but only 8 down.
	for symbol in ["AnimEllipticalGust", "AnimEllipticalGustCentered"]:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		_run_b5(vm, symbol, "gEllipticalGustSpriteTemplate")
		var n := _b5_last
		if n == null:
			_chk("%s spawns" % symbol, false)
			continue
		var xs := [n.centre.x]
		var ys := [n.centre.y]
		for i in range(40):
			_step(vm, 1)
			if is_instance_valid(n):
				xs.append(n.centre.x); ys.append(n.centre.y)
		var xr: float = (xs.max() as float) - (xs.min() as float)
		var yr: float = (ys.max() as float) - (ys.min() as float)
		_chk("%s orbits far wider than tall (%.0f vs %.0f)" % [symbol, xr, yr],
				xr > yr * 2.0)
		_step(vm, 45)
		_chk("%s ends on its own 71 frames" % symbol, vm.visual_count() == 0)

	# GustToTarget is the plain linear-travel member of the same family.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[2] = 0; vm2.args[3] = 0; vm2.args[4] = 10
	_run_b5(vm2, "AnimGustToTarget", "gGustToTargetSpriteTemplate")
	var g := _b5_last
	if g != null:
		var d0 := g.centre.distance_to(stage2.center_of(AnimStage.ANIM_TARGET))
		_step(vm2, 8)
		var d1 := g.centre.distance_to(stage2.center_of(AnimStage.ANIM_TARGET))
		_chk("GustToTarget travels attacker -> target (%.0f -> %.0f)"
				% [d0, d1], d1 < d0)


func _test_batch9_alias_and_two_counters() -> void:
	# AnimRockBlastRock IS TranslateAnimSpriteToTargetMonLocation, which M36C
	# already ported. Asserted as one shared implementation so nobody later
	# "fixes" the duplication into a divergent pair.
	_chk("RockBlastRock is registered", _registry.get_behavior(
			"AnimRockBlastRock") != Callable())
	_chk("Rock Blast (350) is playable", _dispatcher.can_play_move(350))

	# FirePlume has TWO independent counters -- it drifts for arg3 frames but
	# LIVES for arg2, so it coasts and then hangs. Collapsing them into one
	# duration is the easy mistake and loses the hang.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0; vm.args[1] = 0
	vm.args[2] = 30   # lifetime
	vm.args[3] = 10   # drift frames
	vm.args[4] = 4; vm.args[5] = -2
	_run_b5(vm, "AnimFirePlume", "gFirePlumeSpriteTemplate")
	var plume := _b5_last
	_chk("fire plume spawns", plume != null)
	if plume == null:
		return
	_step(vm, 9)
	var drifted := plume.centre
	_chk("...drifts while its drift counter runs",
			not drifted.is_equal_approx(Vector2.ZERO))
	_step(vm, 10)
	_chk("...then HANGS once drift ends but life has not",
			plume.centre.is_equal_approx(drifted))
	_chk("...and is still alive during the hang", vm.visual_count() > 0)
	_step(vm, 15)
	_chk("...dying only at its own lifetime", vm.visual_count() == 0)


func _test_batch9_flicker_and_spiral() -> void:
	# ZapCannonSpark's stutter is the whole character of the move: it toggles
	# visibility whenever its angle index divides by 3. A smooth port reads as
	# a different move.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[2] = 10; vm.args[3] = 30; vm.args[4] = 0; vm.args[5] = 5
	_run_b5(vm, "AnimZapCannonSpark", "gZapCannonSparkSpriteTemplate")
	var spark := _b5_last
	_chk("zap spark spawns", spark != null)
	if spark != null:
		var flips := 0
		var was := spark.visible
		for i in range(25):
			_step(vm, 1)
			if is_instance_valid(spark) and spark.visible != was:
				flips += 1
				was = spark.visible
		_chk("...and stutters in flight (%d visibility flips)" % flips,
				flips > 0)

	# IcePunchSwirlingParticle's amplitude accumulates NEGATIVE on a positive
	# base, so the radius passes through zero and back out -- it spirals in,
	# through the centre, and out the far side rather than simply expanding.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[0] = 0
	_run_b5(vm2, "AnimIcePunchSwirlingParticle",
			"gIceCrystalSpiralInwardLarge")
	var ice := _b5_last
	if ice != null:
		var centre := stage2.center_of(AnimStage.ANIM_ATTACKER)
		var radii: Array = []
		for i in range(50):
			_step(vm2, 1)
			if is_instance_valid(ice):
				radii.append(ice.centre.distance_to(centre))
		if radii.size() > 10:
			var lo: float = radii.min()
			var hi: float = radii.max()
			_chk("ice particle's radius genuinely varies (%.1f..%.1f)"
					% [lo, hi], hi - lo > 1.0)

	# MagentaHeart rises steadily while swaying.
	var stage3 := FakeStage.new()
	var vm3 := _vm(stage3)
	_run_b5(vm3, "AnimMagentaHeart", "gMagentaHeartSpriteTemplate")
	var heart := _b5_last
	if heart != null:
		var y0 := heart.centre.y
		var xs: Array = []
		for i in range(30):
			_step(vm3, 1)
			if is_instance_valid(heart):
				xs.append(heart.centre.x)
		_chk("magenta heart rises", heart.centre.y < y0)
		var xr: float = (xs.max() as float) - (xs.min() as float)
		_chk("...while swaying sideways (%.1f px)" % xr, xr > 0.5)
		_step(vm3, 40)
		_chk("...for exactly 60 frames", vm3.visual_count() == 0)


func _test_batch9_droplet_and_deform() -> void:
	# SprayWaterDroplet carries a real upstream BUG, reproduced as written:
	# the step self-assigns `data[0] = data[0]` where it clearly meant to
	# decay the horizontal speed the way it decays the vertical. So y
	# decelerates and x does not. Pinned so a future session does not "fix"
	# the arc into a shape the reference never draws.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0; vm.args[1] = 0
	_run_b5(vm, "AnimSprayWaterDroplet", "gSprayWaterDropletSpriteTemplate")
	var drop := _b5_last
	_chk("water droplet spawns", drop != null)
	if drop != null:
		var p0 := drop.centre
		_step(vm, 1)
		var d1 := drop.centre - p0
		# The vertical speed is 8.8 fixed point decaying 32/frame from ~896,
		# so it takes 6 frames to lose a whole pixel -- the same truncation
		# shape as FlyBallUp. Comparing adjacent frames would tie at 3px and
		# prove nothing, so the later sample is taken well past that point.
		_step(vm, 9)
		var p1 := drop.centre
		_step(vm, 1)
		var d2 := drop.centre - p1
		_chk("...its horizontal speed does NOT decay (upstream bug, kept)",
				is_equal_approx(absf(d1.x), absf(d2.x)))
		_chk("...while its rise DOES decelerate (%.1f -> %.1f px/frame)"
				% [absf(d1.y), absf(d2.y)], absf(d2.y) < absf(d1.y))
		_step(vm, 30)
		_chk("...over exactly 31 frames", vm.visual_count() == 0)

	# DefenseCurlDeformMon's two affine halves cancel EXACTLY, so it is
	# self-restoring by construction rather than by a corrective final step.
	var stage2 := FakeStage.new()
	var node: Control = stage2.nodes[AnimStage.ANIM_ATTACKER]
	var base := node.scale
	var vm2 := _vm(stage2)
	_registry.get_behavior("AnimTask_DefenseCurlDeformMon").call(vm2, {})
	var widest := base.x
	var flattest := base.y
	for i in range(40):
		_step(vm2, 1)
		widest = maxf(widest, node.scale.x)
		flattest = minf(flattest, node.scale.y)
		if vm2.visual_count() == 0:
			break
	# Inverted affine: a NEGATIVE x delta widens, the positive y delta flattens.
	_chk("Defense Curl squashes the mon wider (%.3f > %.3f)"
			% [widest, base.x], widest > base.x)
	_chk("...and flatter (%.3f < %.3f)" % [flattest, base.y], flattest < base.y)
	_chk("...and restores its scale exactly", node.scale.is_equal_approx(base))
	_chk("Defense Curl (111) is playable", _dispatcher.can_play_move(111))


func _test_batch9_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 516 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 516)
	# The headliners this batch unblocked, named so a regression is legible.
	for pair in [[19, "Fly"], [118, "Metronome"], [8, "Ice Punch"],
			[82, "Dragon Rage"], [16, "Gust"], [30, "Horn Attack"],
			[304, "Hyper Voice"]]:
		_chk("%s is playable" % str(pair[1]),
				_dispatcher.can_play_move(int(pair[0])))


# ── [M36D batch 10] ───────────────────────────────────────────────────────
#
# The curve flattened here as batch 9's closing measurement warned. 11 of 16
# candidates shipped; five were DEFERRED rather than guessed at, because
# their step functions were not read in full. What is here is tested on the
# beats a half-read port would drop -- holds, dead waits, and phase splits.


func _test_batch10_alias_and_flash() -> void:
	# AnimFireSpiralInward is byte-identical to batch 9's ice-punch particle:
	# same driver, same four constants. Asserted as ONE implementation so the
	# duplication is not later "fixed" into a divergent pair.
	_chk("FireSpiralInward and IcePunchSwirlingParticle share one impl",
			_registry.get_behavior("AnimFireSpiralInward")
			== _registry.get_behavior("AnimIcePunchSwirlingParticle"))

	# Flash slams to black/white, HOLDS, and only then fades. The hold is the
	# beat a port drops by accident.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_Flash").call(vm, {})
	var mon: Control = stage.nodes[AnimStage.ANIM_ATTACKER]
	_chk("Flash blends the battlers immediately",
			mon.material != null)
	_step(vm, 5)
	_chk("...and HOLDS before fading (still running at frame 5)",
			vm.visual_count() > 0)
	_step(vm, 45)
	_chk("...then finishes on its own ~39 frames", vm.visual_count() == 0)
	_chk("...leaving no blend behind on the battler", mon.material == null)


func _test_batch10_orbit_and_flickers() -> void:
	# ReversalOrb's ellipse widens FOUR TIMES as fast as it heightens
	# (0x400 vs 0x100 per frame), then unwinds symmetrically back to nothing.
	# A circular port, or one that only grows, both look plausible and are
	# wrong in different ways.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 20; vm.args[1] = 0
	_run_b5(vm, "AnimReversalOrb", "gReversalOrbSpriteTemplate")
	var orb := _b5_last
	_chk("reversal orb spawns", orb != null)
	if orb != null:
		var centre := stage.center_of(AnimStage.ANIM_ATTACKER)
		var xs: Array = []
		var ys: Array = []
		for i in range(20):
			_step(vm, 1)
			if is_instance_valid(orb):
				xs.append(absf(orb.centre.x - centre.x))
				ys.append(absf(orb.centre.y - centre.y))
		var xmax: float = xs.max()
		var ymax: float = ys.max()
		_chk("...orbits far wider than tall (%.0f vs %.0f)" % [xmax, ymax],
				xmax > ymax * 2.0)
		_step(vm, 25)
		_chk("...and unwinds back closed", vm.visual_count() == 0)

	# BlackSmoke flickers EVERY frame -- that is what makes it read as smoke
	# rather than a sliding sprite.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[0] = 0; vm2.args[1] = 0; vm2.args[2] = 256
	vm2.args[3] = 0; vm2.args[4] = 12
	_run_b5(vm2, "AnimBlackSmoke", "gBlackSmokeSpriteTemplate")
	var smoke := _b5_last
	if smoke != null:
		var flips := 0
		var was := smoke.visible
		for i in range(8):
			_step(vm2, 1)
			if is_instance_valid(smoke) and smoke.visible != was:
				flips += 1
				was = smoke.visible
		_chk("black smoke flickers on EVERY frame (%d/8)" % flips, flips >= 7)

	# OutrageFlame starts INVISIBLE and blinks into existence mid-flight.
	var stage3 := FakeStage.new()
	var vm3 := _vm(stage3)
	vm3.args[0] = 0; vm3.args[1] = 0; vm3.args[2] = 20
	vm3.args[3] = 256; vm3.args[4] = 0; vm3.args[5] = 3
	_run_b5(vm3, "AnimOutrageFlame", "gOutrageFlameSpriteTemplate")
	var flame := _b5_last
	if flame != null:
		_chk("outrage flame starts INVISIBLE", not flame.visible)
		var appeared := false
		for i in range(12):
			_step(vm3, 1)
			if is_instance_valid(flame) and flame.visible:
				appeared = true
		_chk("...and blinks into existence mid-flight", appeared)


func _test_batch10_phases() -> void:
	# SurroundingRing starts BELOW the attacker and sweeps up through it --
	# not an expanding ring, despite the name.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_run_b5(vm, "SpriteCB_SurroundingRing", "gAuroraVeilRingTemplate")
	var ring := _b5_last
	if ring != null:
		var c := stage.center_of(AnimStage.ANIM_ATTACKER)
		_chk("surrounding ring starts BELOW the attacker", ring.centre.y > c.y)
		_step(vm, 13)
		_chk("...and ends above where it began", ring.centre.y < c.y)

	# FallingObject has two genuinely separate phases: it FALLS, and only on
	# landing does it flicker out. Merging them loses the landing beat.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[0] = 0; vm2.args[1] = 40; vm2.args[2] = 4
	vm2.args[3] = AnimStage.ANIM_TARGET
	_run_b5(vm2, "SpriteCB_FallingObject", "gContinentalCrushBigRockStompSpriteTemplate")
	var obj := _b5_last
	if obj != null:
		var rest := stage2.center_of(AnimStage.ANIM_TARGET)
		_chk("falling object starts above its target", obj.centre.y < rest.y)
		var fell := false
		for i in range(40):
			_step(vm2, 1)
			if is_instance_valid(obj) and absf(obj.centre.y - rest.y) < 1.0:
				fell = true
				break
		_chk("...falls to the target's level", fell)
		_chk("...and is still alive to flicker there", vm2.visual_count() > 0)
		_step(vm2, 15)
		_chk("...then goes", vm2.visual_count() == 0)

	# GuillotinePincer's middle phase is the whole character of the move: a
	# 51-frame grind jittering every frame. Porting only the converge gives a
	# pincer that arrives and politely stops.
	var stage3 := FakeStage.new()
	var vm3 := _vm(stage3)
	vm3.args[0] = 0
	_run_b5(vm3, "AnimGuillotinePincer", "gGuillotineSpriteTemplate")
	var pincer := _b5_last
	if pincer != null:
		var target := stage3.center_of(AnimStage.ANIM_TARGET)
		var d0 := pincer.centre.distance_to(target)
		_step(vm3, 6)
		var d1 := pincer.centre.distance_to(target)
		_chk("pincer converges (%.0f -> %.0f)" % [d0, d1], d1 < d0)
		# During the grind it must move every frame, never settle.
		var moves := 0
		var prev := pincer.centre
		for i in range(10):
			_step(vm3, 1)
			if is_instance_valid(pincer) and not pincer.centre.is_equal_approx(prev):
				moves += 1
				prev = pincer.centre
		_chk("...then GRINDS rather than settling (%d/10 frames moved)" % moves,
				moves >= 9)
		_step(vm3, 60)
		_chk("...and retreats away again", vm3.visual_count() == 0)

	# Spikes: arc, then a DEAD 30-frame hold, then flicker on ODD frames only.
	var stage4 := FakeStage.new()
	var vm4 := _vm(stage4)
	vm4.args[2] = 0; vm4.args[3] = 0; vm4.args[4] = 10
	_run_b5(vm4, "AnimSpikes", "gSpikesSpriteTemplate")
	var spike := _b5_last
	if spike != null:
		var a := spike.centre
		var b := stage4.center_of(AnimStage.ANIM_TARGET)
		_step(vm4, 5)
		# Mid-arc it must sit ABOVE the straight line between the endpoints.
		var straight_y: float = a.y + (b.y - a.y) * 0.5
		_chk("spikes LOB rather than travelling straight (%.0f < %.0f)"
				% [spike.centre.y, straight_y], spike.centre.y < straight_y)
		_step(vm4, 5)
		var landed := spike.centre
		_step(vm4, 20)
		_chk("...then sit DEAD STILL for the hold",
				spike.centre.is_equal_approx(landed))
		_chk("...still alive during it", vm4.visual_count() > 0)
		_step(vm4, 30)
		_chk("...before flickering out", vm4.visual_count() == 0)

	# QuestionMark is placed from the attacker's own SPRITE SIZE, not a fixed
	# offset -- so a bigger mon puts it further out.
	var stage5 := FakeStage.new()
	var vm5 := _vm(stage5)
	_run_b5(vm5, "AnimQuestionMark", "gQuestionMarkSpriteTemplate")
	var q := _b5_last
	if q != null:
		var mon: Control = stage5.nodes[AnimStage.ANIM_ATTACKER]
		var c := stage5.center_of(AnimStage.ANIM_ATTACKER)
		_chk("question mark offsets by the mon's own half-size",
				is_equal_approx(absf(q.centre.x - c.x), mon.size.x * 0.5))
		_chk("...and sits above its centre", q.centre.y < c.y)


func _test_batch10_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 543 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 543)
	# Batch 10 deferred five behaviors and asserted all five stayed
	# unregistered. Batch 11 ported four of them after reading their step
	# functions, so that assertion is legitimately invalidated -- rewritten
	# here rather than deleted, and split so the one STILL deferred is
	# guarded on its own.
	for sym in ["AnimTask_Rollout", "AnimTask_FlailMovement",
			"AnimTask_NightmareClone", "AnimTask_ShrinkTargetCopy"]:
		_chk("%s was deferred by batch 10 and is now ported" % sym,
				_registry.get_behavior(sym) != Callable())
	# Batch 11 asserted SpiteTargetShadow stayed deferred. Reading its steps in
	# full overturned that call -- see _test_batch11_spite_overturns_deferral.
	_chk("AnimTask_SpiteTargetShadow is now ported (deferral overturned)",
			_registry.get_behavior("AnimTask_SpiteTargetShadow") != Callable())


# ── [M36D batch 11] ───────────────────────────────────────────────────────
#
# Four of batch 10's five deferrals, ported once their step functions were
# actually read. The headline is a NEW LEAK CLASS the reading exposed:
# AnimTask_ShrinkTargetCopy shrinks the REAL target and waits for a script
# signal to restore it, so a run that ends first would strand a shrunk
# Pokemon -- the same shape as batch 7's Extreme Speed visibility pair, but
# on scale, which none of the VM's three existing nets covered.


func _test_batch11_scale_leak_net() -> void:
	var stage := FakeStage.new()
	var node: Control = stage.nodes[AnimStage.ANIM_TARGET]
	var base := node.scale

	var vm := _vm(stage)
	vm.args[0] = 256; vm.args[1] = 8
	_registry.get_behavior("AnimTask_ShrinkTargetCopy").call(vm, {})
	_step(vm, 8)
	# Inverted affine: the parameter CLIMBS, so the sprite must get SMALLER.
	_chk("ShrinkTargetCopy shrinks the target (%.3f < %.3f)"
			% [node.scale.x, base.x], node.scale.x < base.x)
	_chk("...and drifts it sideways",
			not node.position.is_equal_approx(
					node.get_meta("_anim_mon_base")))
	_step(vm, 10)
	_chk("...then HOLDS, waiting for the script's signal",
			node.scale.x < base.x and vm.visual_count() > 0)

	# THE NET: end the run without ever signalling. Nothing in the behavior
	# restores here -- only the VM's fourth restore net can.
	vm._finish()
	_chk("...and a run ending before the signal cannot strand it shrunk",
			node.scale.is_equal_approx(base))
	_chk("...with its position restored too",
			node.position.is_equal_approx(node.get_meta("_anim_mon_base")))

	# The signalled path must also work, or the net would be masking a
	# behavior that never restores at all.
	var stage2 := FakeStage.new()
	var node2: Control = stage2.nodes[AnimStage.ANIM_TARGET]
	var base2 := node2.scale
	var vm2 := _vm(stage2)
	vm2.args[0] = 256; vm2.args[1] = 6
	_registry.get_behavior("AnimTask_ShrinkTargetCopy").call(vm2, {})
	_step(vm2, 10)
	_chk("...(shrunk again, second fixture)", node2.scale.x < base2.x)
	vm2.args[AnimScriptVM.ARG_RET] = -1
	_step(vm2, 2)
	_chk("...the -1 signal restores it through the behavior itself",
			node2.scale.is_equal_approx(base2))
	_chk("...and the task ends there", vm2.visual_count() == 0)

	# An invisible target is a real early-out upstream, not an error.
	var stage3 := FakeStage.new()
	stage3.nodes[AnimStage.ANIM_TARGET].visible = false
	var vm3 := _vm(stage3)
	vm3.args[0] = 256; vm3.args[1] = 6
	_registry.get_behavior("AnimTask_ShrinkTargetCopy").call(vm3, {})
	_chk("...an invisible target runs nothing at all", vm3.visual_count() == 0)


func _test_batch11_decay_and_drift() -> void:
	# FlailMovement DECAYS -- that is what makes it flail rather than wobble.
	# The amplitude loses 0x40 every 9 frames, so late swings are visibly
	# smaller than early ones. A constant-amplitude port looks fine in a
	# still frame and wrong in motion.
	var stage := FakeStage.new()
	var node: Control = stage.nodes[AnimStage.ANIM_ATTACKER]
	var base_rot := node.rotation
	var base_pos := node.position
	var vm := _vm(stage)
	vm.args[0] = AnimStage.ANIM_ATTACKER
	_registry.get_behavior("AnimTask_FlailMovement").call(vm, {})

	var early := 0.0
	for i in range(40):
		_step(vm, 1)
		early = maxf(early, absf(node.rotation - base_rot))
	var late := 0.0
	for i in range(40):
		_step(vm, 1)
		late = maxf(late, absf(node.rotation - base_rot))
	_chk("flail rotates the mon", early > 0.0)
	_chk("...and DECAYS over time (%.4f -> %.4f rad)" % [early, late],
			late < early)
	# The sway is derived from the tilt, not an independent motion.
	_chk("...swaying horizontally as it tilts",
			not node.position.is_equal_approx(base_pos))
	_step(vm, 400)
	_chk("...and restores rotation exactly",
			is_equal_approx(node.rotation, base_rot))
	_chk("...and position exactly", node.position.is_equal_approx(base_pos))

	# NightmareClone: a blended ghost peels away and dissolves, then cleans up.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	var before := stage2.layer_node.get_child_count()
	_registry.get_behavior("AnimTask_NightmareClone").call(vm2, {})
	_chk("nightmare clone is created",
			stage2.layer_node.get_child_count() > before)
	var ghost: Control = null
	for c in stage2.layer_node.get_children():
		if c is Control and c.has_meta("_anim_trace"):
			ghost = c
	# A wrong meta key here silently skips the two assertions below while the
	# suite still reports green -- the exact false-pass shape this project's
	# conventions warn about, and it happened on the first draft. Guarded.
	_chk("...and is findable as an anim-owned clone", ghost != null)
	if ghost != null:
		var p0 := ghost.position
		var a0 := ghost.modulate.a
		_step(vm2, 40)
		_chk("...it drifts away from the target",
				not ghost.position.is_equal_approx(p0))
		_chk("...fading as it goes (%.2f -> %.2f)" % [a0, ghost.modulate.a],
				ghost.modulate.a < a0)
	_step(vm2, 140)
	_chk("...and the task finishes", vm2.visual_count() == 0)


func _test_batch11_rollout_windup() -> void:
	# The wind-up is most of Rollout's character: pull BACK away from the
	# target, HOLD 20 dead frames, return, and only then charge. A port that
	# only charges arrives with no anticipation at all.
	var stage := FakeStage.new()
	var node: Control = stage.nodes[AnimStage.ANIM_ATTACKER]
	var atk := stage.center_of(AnimStage.ANIM_ATTACKER)
	var tgt := stage.center_of(AnimStage.ANIM_TARGET)
	var vm := _vm(stage)
	vm.move_turn = 0
	_registry.get_behavior("AnimTask_Rollout").call(vm, {})

	_step(vm, 10)
	var pulled := node.position
	# Pulling back means moving AWAY from the target.
	var d_start := atk.distance_to(tgt)
	var d_pulled := (pulled + node.size * 0.5).distance_to(tgt)
	_chk("Rollout pulls BACK before charging (%.0f -> %.0f)"
			% [d_start, d_pulled], d_pulled > d_start)

	_step(vm, 15)
	_chk("...then HOLDS dead still through the wind-up",
			node.position.is_equal_approx(pulled))
	_chk("...still running during the hold", vm.visual_count() > 0)

	_step(vm, 200)
	_chk("...and ends back on its mark",
			node.position.is_equal_approx(node.get_meta("_anim_mon_base")))

	# Speed scales with the rollout counter -- a later turn crosses faster.
	var frames: Array = []
	for turn in [0, 4]:
		var st := FakeStage.new()
		var v := _vm(st)
		v.move_turn = turn
		_registry.get_behavior("AnimTask_Rollout").call(v, {})
		var n := 0
		for i in range(400):
			_step(v, 1)
			n += 1
			if v.visual_count() == 0:
				break
		frames.append(n)
	_chk("a later-turn Rollout crosses FASTER (%d < %d frames)"
			% [frames[1], frames[0]], frames[1] < frames[0])


func _test_batch11_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 551 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 551)


func _test_batch11_spite_overturns_deferral() -> void:
	# Batches 10 and 11 both deferred this, the second time on the reading
	# that porting it would ship "the least characteristic third". Reading
	# Step1 case 1 through Step2 in full showed that was wrong. The assertions
	# below are the specific claims that reading produced.
	var stage := FakeStage.new()
	var node: Control = stage.nodes[AnimStage.ANIM_TARGET]
	var vm := _vm(stage)
	var before := stage.layer_node.get_child_count()
	_registry.get_behavior("AnimTask_SpiteTargetShadow").call(vm, {})

	# 1. The tint lands on the REAL TARGET, not the clone -- upstream blends
	#    the mon's own palette, which is the detail that makes the move read
	#    as the target draining rather than as a ghost appearing.
	_chk("Spite tints the REAL target", node.material != null)

	# 2. An un-tinted echo is left behind it.
	_chk("...and leaves a clone behind",
			stage.layer_node.get_child_count() > before)
	var ghost: Control = null
	for c in stage.layer_node.get_children():
		if c is Control and c.has_meta("_anim_trace"):
			ghost = c
	_chk("...which is findable as an anim-owned clone", ghost != null)
	if ghost == null:
		return
	_chk("...and is NOT itself tinted", ghost.material == null)

	# 3. The echo swells in and back out ONCE on a sine envelope, rather than
	#    fading monotonically. Sampled across the full 128 frames.
	var alphas: Array = []
	var xs: Array = []
	for i in range(128):
		_step(vm, 1)
		if is_instance_valid(ghost):
			alphas.append(ghost.modulate.a)
			xs.append(ghost.position.x)
	if alphas.size() > 90:
		var peak: float = alphas.max()
		var mid: float = alphas[64] if alphas.size() > 64 else 0.0
		var late: float = alphas[alphas.size() - 5]
		_chk("...the echo swells in (peak %.2f)" % peak, peak > 0.1)
		_chk("...peaking mid-run rather than at the end (%.2f > %.2f)"
				% [mid, late], mid > late)
		var xr: float = (xs.max() as float) - (xs.min() as float)
		_chk("...and wavers horizontally (%.1f px)" % xr, xr > 1.0)

	# 4. Cleanup: the clone goes and the target's tint is released.
	_step(vm, 10)
	# queue_free() defers to end-of-frame, and this suite steps the VM by hand
	# without yielding to the tree -- so the node stays instance-valid and the
	# accurate check is whether it was queued, not whether it is gone yet.
	_chk("...then the echo is queued for release",
			not is_instance_valid(ghost) or ghost.is_queued_for_deletion())
	_chk("...and the target's tint is released", node.material == null)
	_chk("...and the task ends", vm.visual_count() == 0)


# ── [M36D batch 12] ───────────────────────────────────────────────────────
#
# 9 of 14; five deferred for unread step functions. Step 0 turned up two more
# near-aliases of already-ported work -- the third batch running to do so --
# and the sharper of the two is a pair that differ by exactly ONE SIGN, which
# is precisely the kind of thing that gets collapsed into a single wrong
# implementation.


func _test_batch12_near_aliases() -> void:
	# AnimLargeFlame and AnimFirePlume share their step function, both
	# counters and every argument. They differ by ONE inverted sign on the x
	# drift, so they sweep OPPOSITE ways from the same spawn. Registering them
	# as the same behavior would look right in a still frame and be wrong in
	# motion -- so the test demands they genuinely diverge.
	var drifts: Array = []
	for symbol in ["AnimFirePlume", "AnimLargeFlame"]:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		vm.args[0] = 0; vm.args[1] = 0
		vm.args[2] = 30; vm.args[3] = 20
		vm.args[4] = 8; vm.args[5] = 0
		_run_b5(vm, symbol, "gLargeFlameSpriteTemplate")
		var n := _b5_last
		if n == null:
			_chk("%s spawns" % symbol, false)
			drifts.append(0.0)
			continue
		var x0 := n.centre.x
		_step(vm, 10)
		drifts.append(n.centre.x - x0)
	_chk("FirePlume and LargeFlame both drift (%.1f / %.1f)"
			% [drifts[0], drifts[1]],
			not is_zero_approx(drifts[0]) and not is_zero_approx(drifts[1]))
	_chk("...in OPPOSITE directions -- the one inverted sign",
			signf(drifts[0]) != signf(drifts[1]))
	_chk("...and are NOT registered as the same implementation",
			_registry.get_behavior("AnimFirePlume")
			!= _registry.get_behavior("AnimLargeFlame"))

	# AnimGuardRing is SpriteCB_SurroundingRing plus a doubles-centre branch:
	# both sit 40px below the attacker and rise 72px over 13 frames.
	for symbol in ["SpriteCB_SurroundingRing", "AnimGuardRing"]:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		vm.args[0] = 0
		_run_b5(vm, symbol, "gGuardRingSpriteTemplate")
		var n := _b5_last
		if n == null:
			continue
		var c := stage.center_of(AnimStage.ANIM_ATTACKER)
		_chk("%s starts below the attacker" % symbol, n.centre.y > c.y)
		_step(vm, 13)
		_chk("%s ends above where it began" % symbol, n.centre.y < c.y)

	# GuardRing's arg 0 centres it between the pair; SurroundingRing has no
	# such branch, which is the only real difference between them.
	var s2 := FakeStage.new()
	var v2 := _vm(s2)
	v2.args[0] = 1
	_run_b5(v2, "AnimGuardRing", "gGuardRingSpriteTemplate")
	var centred := _b5_last
	var s3 := FakeStage.new()
	var v3 := _vm(s3)
	v3.args[0] = 0
	_run_b5(v3, "AnimGuardRing", "gGuardRingSpriteTemplate")
	var plain := _b5_last
	if centred != null and plain != null:
		_chk("GuardRing arg 0 genuinely moves it (doubles centre)",
				not is_equal_approx(centred.centre.x, plain.centre.x))


func _test_batch12_shapes() -> void:
	# IsPowerOver99 -- boundary asserted on both sides, since an off-by-one
	# here silently picks the wrong branch of a script.
	for pair in [[99, 0], [100, 1], [40, 0], [250, 1]]:
		var vm := _vm(FakeStage.new())
		vm.move_power = int(pair[0])
		_registry.get_behavior("AnimTask_IsPowerOver99").call(vm, {})
		_chk("power %d -> over99 = %d" % [int(pair[0]), int(pair[1])],
				vm.args[AnimScriptVM.ARG_RET] == int(pair[1]))

	# MudSportDirt rising: up EVERY frame, sideways every OTHER frame. A
	# smooth diagonal would read wrong.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0; vm.args[1] = 8; vm.args[2] = 0
	_run_b5(vm, "AnimMudSportDirt", "gMudsportMudSpriteTemplate")
	var dirt := _b5_last
	if dirt != null:
		var y0 := dirt.centre.y
		var x0 := dirt.centre.x
		_step(vm, 1)
		var moved_x_first := not is_equal_approx(dirt.centre.x, x0)
		_chk("mud rises immediately", dirt.centre.y < y0)
		_chk("...but drifts only on alternate frames", not moved_x_first)
		_step(vm, 1)
		_chk("...drifting on the second", not is_equal_approx(dirt.centre.x, x0))

	# ParticleBurst wanders on a sine rather than arcing, and fades out with
	# VISIBILITY, never alpha.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[0] = 256; vm2.args[1] = 12
	_run_b5(vm2, "AnimParticleBurst", "gRedHeartBurstSpriteTemplate")
	var burst := _b5_last
	if burst != null:
		var ys: Array = []
		for i in range(30):
			_step(vm2, 1)
			if is_instance_valid(burst):
				ys.append(burst.centre.y)
		var yr: float = (ys.max() as float) - (ys.min() as float)
		_chk("particle burst oscillates vertically (%.1f px)" % yr, yr > 1.0)
		var flicked := false
		for i in range(20):
			_step(vm2, 1)
			if is_instance_valid(burst) and not burst.visible:
				flicked = true
		_chk("...and flickers out late in its life", flicked)
		_step(vm2, 20)
		_chk("...then dies", vm2.visual_count() == 0)

	# PoisonJab ROTATES TO FACE its target -- without it the jab arrives
	# sideways.
	var stage3 := FakeStage.new()
	var vm3 := _vm(stage3)
	vm3.args[0] = 40; vm3.args[1] = -40; vm3.args[2] = 10
	_run_b5(vm3, "AnimPoisonJabProjectile", "gPoisonJabProjectileSpriteTemplate")
	var jab := _b5_last
	if jab != null:
		var to_t := stage3.center_of(AnimStage.ANIM_TARGET) - jab.centre
		var want := atan2(to_t.y, to_t.x)
		_chk("poison jab points along its own flight path",
				absf(angle_difference(jab.rotation, want)) < 0.05)

	# PowerSwap ARCS, and its direction flag swaps both endpoints together.
	var stage4 := FakeStage.new()
	var vm4 := _vm(stage4)
	vm4.args[2] = 0; vm4.args[3] = 0; vm4.args[4] = 20; vm4.args[5] = 40
	_run_b5(vm4, "AnimMovePowerSwapGuardSwap", "gPowerSwapGuardSwapSpriteTemplate")
	var orb := _b5_last
	if orb != null:
		var a := stage4.center_of(AnimStage.ANIM_ATTACKER)
		var b := stage4.center_of(AnimStage.ANIM_TARGET)
		_step(vm4, 10)
		var straight_y := a.y + (b.y - a.y) * 0.5
		_chk("power swap ARCS rather than travelling straight",
				not is_equal_approx(orb.centre.y, straight_y))
	var stage5 := FakeStage.new()
	var vm5 := _vm(stage5)
	vm5.args[2] = 0; vm5.args[3] = 1; vm5.args[4] = 20; vm5.args[5] = 40
	_run_b5(vm5, "AnimMovePowerSwapGuardSwap", "gPowerSwapGuardSwapSpriteTemplate")
	var rev := _b5_last
	if rev != null:
		_chk("...and its direction flag starts it at the OTHER battler",
				rev.centre.distance_to(stage5.center_of(AnimStage.ANIM_TARGET))
				< rev.centre.distance_to(stage5.center_of(AnimStage.ANIM_ATTACKER)))

	# BlockX's drop height is SIDE-DEPENDENT: 144px player, 96px opponent.
	var heights: Array = []
	for player in [true, false]:
		var st := FakeStage.new()
		st.player_side = not player   # target is on the player's side when
		var v := _vm(st)              # the attacker is not
		_run_b5(v, "AnimBlockX", "gBlockXSpriteTemplate")
		var x := _b5_last
		heights.append(0.0 if x == null
				else st.center_of(AnimStage.ANIM_TARGET).y - x.centre.y)
	_chk("BlockX's drop height differs by side (%.0f vs %.0f)"
			% [heights[0], heights[1]],
			not is_equal_approx(heights[0], heights[1]))

	# BlendNonAttackerPalettes must blend everyone EXCEPT the attacker.
	var stage6 := FakeStage.new()
	var vm6 := _vm(stage6)
	vm6.args[0] = 0; vm6.args[1] = 0; vm6.args[2] = 16; vm6.args[3] = 0x7C00
	_registry.get_behavior("AnimTask_BlendNonAttackerPalettes").call(vm6, {})
	_step(vm6, 20)
	_chk("blend skips the ATTACKER",
			stage6.nodes[AnimStage.ANIM_ATTACKER].material == null)
	_chk("...and reaches the target",
			stage6.nodes[AnimStage.ANIM_TARGET].material != null)


func _test_batch12_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 571 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 571)
	# Batch 12 deferred five and asserted all five stayed unregistered. Batch
	# 13 ported four of them, so that assertion is legitimately invalidated --
	# rewritten, with the one still deferred guarded on its own.
	for sym in ["AnimFlyingParticle", "SpriteCB_Geyser", "AnimTrickBag",
			"AnimSuperpowerFireball"]:
		_chk("%s was deferred by batch 12 and is now ported" % sym,
				_registry.get_behavior(sym) != Callable())
	_chk("AnimFallingFeather was deferred by batch 13 and is now ported",
			_registry.get_behavior("AnimFallingFeather") != Callable())


# ── [M36D batch 13] ───────────────────────────────────────────────────────
#
# Deliberately small: four of batch 12's five deferrals, ported once their
# step functions were read. The alias pattern held for a FOURTH consecutive
# batch, and both hits are against work from the two batches immediately
# prior -- which is why they are asserted as shared implementations rather
# than merely as present.


func _test_batch13_deferrals_cleared() -> void:
	# SpriteCB_Geyser hands straight over to AnimMudSportDirtRising upstream,
	# which batch 12 ported. Same rise-and-drift: up every frame, sideways
	# only every other.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[1] = 8; vm.args[2] = 0
	_run_b5(vm, "SpriteCB_Geyser", "gMudsportMudSpriteTemplate")
	var g := _b5_last
	_chk("geyser spawns", g != null)
	if g != null:
		var y0 := g.centre.y
		var x0 := g.centre.x
		_step(vm, 1)
		_chk("...rises immediately", g.centre.y < y0)
		_chk("...but does not drift on frame 1",
				is_equal_approx(g.centre.x, x0))
		_step(vm, 1)
		_chk("...drifting on frame 2", not is_equal_approx(g.centre.x, x0))

	# SuperpowerFireball IS GrowingSuperpower -- same 16-frame translation
	# between the same endpoints. Asserted as ONE implementation.
	_chk("SuperpowerFireball and GrowingSuperpower share one impl",
			_registry.get_behavior("AnimSuperpowerFireball")
			== _registry.get_behavior("SpriteCB_GrowingSuperpower"))

	# FlyingParticle crosses the WHOLE SCREEN and dies at the far edge -- it
	# has no duration argument at all, which is the tell that a port must not
	# invent one.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[0] = 60; vm2.args[1] = 8; vm2.args[2] = 0
	vm2.args[3] = 6; vm2.args[4] = 8; vm2.args[5] = 0; vm2.args[6] = 0
	_run_b5(vm2, "AnimFlyingParticle", "gAromatherapyBigFlowerSpriteTemplate")
	var fp := _b5_last
	if fp != null:
		var x0 := fp.centre.x
		_chk("flying particle starts off-screen", x0 < 0.0 or x0 > 1024.0)
		var ys: Array = []
		for i in range(30):
			_step(vm2, 1)
			if is_instance_valid(fp):
				ys.append(fp.centre.y)
		_chk("...travels horizontally", absf(fp.centre.x - x0) > 10.0)
		var yr: float = (ys.max() as float) - (ys.min() as float)
		_chk("...wobbling vertically as it goes (%.1f px)" % yr, yr > 1.0)
		_step(vm2, 400)
		_chk("...and dies by clearing the far edge, not on a counter",
				vm2.visual_count() == 0)

	# TrickBag spawns at SCREEN CENTRE rather than on a battler, falls with
	# real acceleration, then orbits a WIDE FLAT ellipse (x radius 60 against
	# y radius 20 -- the axes are the reverse of the usual convention).
	var stage3 := FakeStage.new()
	var vm3 := _vm(stage3)
	vm3.args[0] = 8; vm3.args[1] = 0
	_run_b5(vm3, "AnimTrickBag", "gTrickBagSpriteTemplate")
	var bag := _b5_last
	if bag != null:
		var atk := stage3.center_of(AnimStage.ANIM_ATTACKER)
		_chk("trick bag spawns at screen centre, not on a battler",
				absf(bag.centre.x - atk.x) > 50.0)
		var y0 := bag.centre.y
		_step(vm3, 1)
		var d1 := bag.centre.y - y0
		var y1 := bag.centre.y
		_step(vm3, 4)
		var d2 := (bag.centre.y - y1) / 4.0
		_chk("...falls with real acceleration (%.2f -> %.2f px/frame)"
				% [d1, d2], d2 > d1)
		# Once orbiting, the path must be far wider than it is tall.
		_step(vm3, 40)
		var xs: Array = []
		var ys2: Array = []
		for i in range(40):
			_step(vm3, 1)
			if is_instance_valid(bag):
				xs.append(bag.centre.x); ys2.append(bag.centre.y)
		if xs.size() > 20:
			var xr: float = (xs.max() as float) - (xs.min() as float)
			var yr2: float = (ys2.max() as float) - (ys2.min() as float)
			_chk("...then orbits a WIDE FLAT ellipse (%.0f vs %.0f)"
					% [xr, yr2], xr > yr2)
		_step(vm3, 200)
		_chk("...and ends at the table's sentinel row",
				vm3.visual_count() == 0)

	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 580 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 580)


# ── Suite self-check ──────────────────────────────────────────────────────

func _test_every_template_name_resolves() -> void:
	# Eight template names in this suite were WRONG and nobody noticed, because
	# every spawning test guards on `if node != null:` -- so a name that failed
	# to resolve skipped its assertions silently while the suite still reported
	# green. 26 assertions across batches 8-13 were not running.
	#
	# This reads the suite's own source and requires every template it names to
	# resolve, so the failure mode is a red test rather than a quiet skip. It
	# is self-maintaining: a new batch naming a bad template fails here without
	# anyone remembering to extend a list.
	var f := FileAccess.open(
			"res://scenes/battle/m36d_batch_test.gd", FileAccess.READ)
	if f == null:
		_chk("suite source is readable for the template self-check", false)
		return
	var src := f.get_as_text()
	f.close()
	var re := RegEx.new()
	re.compile("\"(g[A-Za-z0-9_]*Template)\"")
	var seen := {}
	for m in re.search_all(src):
		seen[m.get_string(1)] = true
	var bad: Array = []
	for name in seen:
		if (AnimData.template(str(name)) as Dictionary).is_empty():
			bad.append(str(name))
	_chk("all %d template names in this suite resolve (bad: %s)"
			% [seen.size(), ", ".join(bad) if not bad.is_empty() else "none"],
			bad.is_empty())


# ── [M36D batch 14] ───────────────────────────────────────────────────────

func _test_batch14_rotate_and_travel() -> void:
	# The fifth alias family, and the first that is a family rather than a
	# pair: PsychoCut, SonicBoom, TealAlert and (rerouted) PoisonJab all
	# "rotate to face the destination, then travel", differing ONLY in a
	# rest-angle correction constant per sprite sheet.
	#
	# The failure this guards is a copy-paste: reuse one constant for all four
	# and every path is still correct while the artwork flies sideways. So the
	# test demands the SAME geometry produce FOUR DISTINCT rotations.
	var rots := {}
	var cases := [
		["AnimPsychoCut", "gPsychoCutSpriteTemplate", false],
		["AnimSonicBoomProjectile", "gSonicBoomSpriteTemplate", false],
		["AnimTealAlert", "gTealAlertSpriteTemplate", true],
		["AnimPoisonJabProjectile", "gPoisonJabProjectileSpriteTemplate", true],
	]
	for c in cases:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		# Non-zero spawn offsets, so the facing term is real for all four
		# rather than degenerate for the two that spawn on the target.
		vm.args[0] = 30; vm.args[1] = -20; vm.args[2] = 10
		vm.args[3] = 0; vm.args[4] = 10
		_run_b5(vm, str(c[0]), str(c[1]))
		var n := _b5_last
		if n == null:
			_chk("%s spawns" % str(c[0]), false)
			continue
		_chk("%s spawns" % str(c[0]), true)
		rots[str(c[0])] = n.rotation
	var vals: Array = rots.values()
	var distinct := {}
	for v in vals:
		distinct[snappedf(float(v), 0.001)] = true
	_chk("all four rest-angle corrections are DISTINCT (%d/%d unique)"
			% [distinct.size(), vals.size()],
			distinct.size() == vals.size() and vals.size() == 4)

	# And each must genuinely point along its own flight path, not at a fixed
	# screen angle -- checked by giving one a different destination and
	# requiring its rotation to move with it.
	var seen: Array = []
	for dy in [-40, 40]:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		vm.args[0] = 0; vm.args[1] = 0; vm.args[2] = 0
		vm.args[3] = dy; vm.args[4] = 10
		_run_b5(vm, "AnimPsychoCut", "gPsychoCutSpriteTemplate")
		if _b5_last != null:
			seen.append(_b5_last.rotation)
	if seen.size() == 2:
		_chk("...and the angle tracks the destination, not a fixed screen angle",
				not is_equal_approx(seen[0], seen[1]))


func _test_batch14_shapes() -> void:
	# RedHeartProjectile has NO duration argument -- a fixed 95 frames, which
	# is what gives Attract its unhurried drift.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_run_b5(vm, "AnimRedHeartProjectile", "gRedHeartProjectileSpriteTemplate")
	var heart := _b5_last
	if heart != null:
		var ys: Array = []
		for i in range(40):
			_step(vm, 1)
			if is_instance_valid(heart):
				ys.append(heart.centre.y)
		_chk("red heart sways vertically in flight",
				(ys.max() as float) - (ys.min() as float) > 1.0)
		_step(vm, 50)
		_chk("...still alive just before frame 95", vm.visual_count() > 0)
		_step(vm, 10)
		_chk("...and ends at its fixed 95", vm.visual_count() == 0)

	# HitSplatRandom scatters in a DELIBERATELY ASYMMETRIC box: +/-24 across
	# but only +/-12 down, so repeated hits spread ALONG the target.
	var xs: Array = []
	var ys2: Array = []
	for i in range(40):
		var st := FakeStage.new()
		var v := _vm(st)
		v.args[0] = AnimStage.ANIM_TARGET; v.args[1] = -1
		_run_b5(v, "AnimHitSplatRandom", "gBasicHitSplatSpriteTemplate")
		if _b5_last != null:
			var c := st.center_of(AnimStage.ANIM_TARGET)
			xs.append(_b5_last.centre.x - c.x)
			ys2.append(_b5_last.centre.y - c.y)
	if xs.size() > 20:
		var xspread: float = (xs.max() as float) - (xs.min() as float)
		var yspread: float = (ys2.max() as float) - (ys2.min() as float)
		_chk("hit splats scatter (%.0f x %.0f px over %d samples)"
				% [xspread, yspread, xs.size()], xspread > 0.0)
		_chk("...wider than they are tall -- along the target, not around it",
				xspread > yspread)

	# SpiderWeb HOLDS 20 dead frames before fading, and fades one step every
	# OTHER frame so the 16-step fade takes 32.
	var stage3 := FakeStage.new()
	var vm3 := _vm(stage3)
	vm3.args[0] = 0; vm3.args[1] = 0; vm3.args[2] = 0
	_run_b5(vm3, "AnimSpiderWeb", "gSpiderWebSpriteTemplate")
	var web := _b5_last
	if web != null:
		_step(vm3, 18)
		_chk("spider web holds fully opaque through its dead frames",
				is_equal_approx(web.modulate.a, 1.0))
		_step(vm3, 20)
		_chk("...then begins fading", web.modulate.a < 1.0)
		_chk("...still fading at frame 38 (one step every OTHER frame)",
				vm3.visual_count() > 0)
		_step(vm3, 40)
		_chk("...and is gone by ~52", vm3.visual_count() == 0)

	# WebThread's arg 2 is a SPEED, not a duration -- so a farther target must
	# take LONGER. A port that treats it as a frame count ties here.
	var times: Array = []
	for far in [false, true]:
		var st := FakeStage.new()
		if far:
			st.nodes[AnimStage.ANIM_TARGET].position += Vector2(400, 0)
		var v := _vm(st)
		v.args[0] = 0; v.args[1] = 0; v.args[2] = 4; v.args[3] = 6; v.args[4] = 0
		_run_b5(v, "AnimTranslateWebThread", "gWebThreadSpriteTemplate")
		var n := 0
		for i in range(600):
			_step(v, 1)
			n += 1
			if v.visual_count() == 0:
				break
		times.append(n)
	_chk("web thread's arg 2 is a SPEED -- farther takes longer (%d < %d)"
			% [times[0], times[1]], times[1] > times[0])

	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 593 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 593)
	# Batch 15 deferred four; all four were cleared the same day once the
	# search failures behind three of them were found. Nothing is deferred.
	for sym in ["AnimDiveBall", "AnimDiveWaterSplash",
			"SpriteCB_ToxicThreadWrap",
			"SpriteCB_SpriteOnMonUntilAffineAnimEnds"]:
		_chk("%s is now ported (deferral was a search failure)" % sym,
				_registry.get_behavior(sym) != Callable())
	# Deferred by batches 12, 13 AND 14, then taken directly.
	_chk("AnimFallingFeather is ported (thrice-deferred, taken directly)",
			_registry.get_behavior("AnimFallingFeather") != Callable())


# ── AnimFallingFeather ────────────────────────────────────────────────────
#
# The last deferral, taken directly. Its 247 lines are mostly one flip block
# copy-pasted into four switch arms; the mechanic underneath is small. These
# assertions target the three details that make it read as a FEATHER rather
# than a pendulum -- each is something a plausible-looking port would drop.


func _feather_vm(stage: FakeStage, amp_lo: int, amp_hi: int) -> AnimScriptVM:
	var vm := _vm(stage)
	vm.args[0] = 0; vm.args[1] = -40
	vm.args[2] = 0            # phase 0, rotation base 0
	vm.args[3] = 4            # phase step, ascending
	vm.args[4] = 96           # fall speed (8.8)
	vm.args[5] = amp_lo | (amp_hi << 8)
	vm.args[6] = 120          # y limit
	vm.args[7] = 0
	return vm


func _test_falling_feather() -> void:
	# 1. TWO ALTERNATING AMPLITUDES. `unkC` is a two-byte array indexed by a
	#    flag toggled at one quadrant boundary, so consecutive swings are
	#    DIFFERENT widths. A port using a single amplitude produces a clean
	#    sine that looks fine in isolation and wrong over time.
	var stage := FakeStage.new()
	var vm := _feather_vm(stage, 6, 40)
	_run_b5(vm, "AnimFallingFeather", "gFallingFeatherSpriteTemplate")
	var f := _b5_last
	_chk("falling feather spawns", f != null)
	if f == null:
		return
	var x0 := f.centre.x
	var swing_peaks: Array = []
	var cur := 0.0
	var prev_sign := 0
	for i in range(200):
		_step(vm, 1)
		if not is_instance_valid(f):
			break
		var dx := f.centre.x - x0
		var sgn := signi(int(dx))
		if sgn != 0 and prev_sign != 0 and sgn != prev_sign:
			if cur > 0.0:
				swing_peaks.append(cur)
			cur = 0.0
		if sgn != 0:
			prev_sign = sgn
		cur = maxf(cur, absf(dx))
	var widest := 0.0
	var narrowest := 99999.0
	for p in swing_peaks:
		widest = maxf(widest, float(p))
		narrowest = minf(narrowest, float(p))
	_chk("feather swings at least twice (%d)" % swing_peaks.size(),
			swing_peaks.size() >= 2)
	if swing_peaks.size() >= 2:
		_chk("...with ALTERNATING widths, not one clean sine (%.0f vs %.0f)"
				% [widest, narrowest], widest > narrowest * 1.5)

	# 2. TILT IS DERIVED FROM HORIZONTAL OFFSET, not from elapsed time. So the
	#    rotation at the sway extreme must differ from the rotation near
	#    centre -- a time-driven port would keep turning regardless.
	var stage2 := FakeStage.new()
	var vm2 := _feather_vm(stage2, 30, 30)
	_run_b5(vm2, "AnimFallingFeather", "gFallingFeatherSpriteTemplate")
	var f2 := _b5_last
	if f2 != null:
		var bx := f2.centre.x
		var samples: Array = []
		for i in range(60):
			_step(vm2, 1)
			if is_instance_valid(f2):
				samples.append([absf(f2.centre.x - bx), f2.rotation])
		if samples.size() > 30:
			# Compare the rotation at the widest offset against the narrowest.
			samples.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
			var near: float = float(samples[0][1])
			var far: float = float(samples[samples.size() - 1][1])
			_chk("feather's tilt tracks its own drift (%.3f vs %.3f rad)"
					% [near, far], not is_equal_approx(near, far))

	# 3. THE FLIP AND THE DRAW-ORDER SWAP HAPPEN TOGETHER -- the feather
	#    turning over as it passes in front of or behind the Pokemon.
	var stage3 := FakeStage.new()
	var vm3 := _feather_vm(stage3, 30, 30)
	_run_b5(vm3, "AnimFallingFeather", "gFallingFeatherSpriteTemplate")
	var f3 := _b5_last
	if f3 != null:
		var flips := 0
		var z_changes := 0
		var last_sign := signf(f3.scale.x)
		var last_z := f3.z_index
		for i in range(200):
			_step(vm3, 1)
			if not is_instance_valid(f3):
				break
			if signf(f3.scale.x) != last_sign:
				flips += 1
				last_sign = signf(f3.scale.x)
			if f3.z_index != last_z:
				z_changes += 1
				last_z = f3.z_index
		_chk("feather flips over as it falls (%d flips)" % flips, flips > 0)
		_chk("...and its draw order changes with the flip (%d vs %d)"
				% [flips, z_changes], z_changes == flips)

	# 4. It falls at a CONSTANT rate and dies at its own y limit, not on a
	#    frame counter.
	var stage4 := FakeStage.new()
	var vm4 := _feather_vm(stage4, 20, 20)
	_run_b5(vm4, "AnimFallingFeather", "gFallingFeatherSpriteTemplate")
	var f4 := _b5_last
	if f4 != null:
		var y0 := f4.centre.y
		# Upstream a PAUSED frame skips the whole motion block, so the feather
		# does not fall on the beat between swings. The descent is therefore
		# constant BETWEEN pauses, not overall -- a first draft asserting a
		# flat rate failed at 16.00 vs 14.40, which is exactly nine moving
		# frames and one paused one. The precise claim is that every frame's
		# delta is either zero or the SAME constant.
		var deltas := {}
		var prev := f4.centre.y
		for i in range(40):
			_step(vm4, 1)
			if not is_instance_valid(f4):
				break
			deltas[snappedf(f4.centre.y - prev, 0.01)] = true
			prev = f4.centre.y
		_chk("feather falls", prev > y0)
		_chk("...at one constant rate, with paused frames at zero (%s)"
				% str(deltas.keys()), deltas.size() <= 2)
		_chk("...and one of those values is a genuine pause",
				deltas.has(0.0) or deltas.size() == 1)
		_step(vm4, 400)
		_chk("...and ends at its y limit", vm4.visual_count() == 0)


# ── [M36D batch 15] ───────────────────────────────────────────────────────

func _test_batch15() -> void:
	# The sixth alias: the on-target orb is batch 8's orb on a different
	# battler. Shared body, different anchor.
	var orbs := {}
	for pair in [["AnimGrowingShockWaveOrb", AnimStage.ANIM_ATTACKER],
			["AnimGrowingShockWaveOrbOnTarget", AnimStage.ANIM_TARGET]]:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		_run_b5(vm, str(pair[0]), "gGrowingShockWaveOrbSpriteTemplate")
		var n := _b5_last
		_chk("%s spawns" % str(pair[0]), n != null)
		if n != null:
			_chk("...on the right battler",
					n.centre.distance_to(stage.center_of(int(pair[1]))) < 1.0)
			orbs[str(pair[0])] = n.centre
	if orbs.size() == 2:
		_chk("...and the two anchor to DIFFERENT battlers",
				not (orbs.values()[0] as Vector2).is_equal_approx(
						orbs.values()[1] as Vector2))

	# THE HEADLINE: Petal Dance's two flowers have near-identical setups --
	# which is what made them look like an alias pair -- but genuinely
	# different steps. Big sways WIDE and bobs vertically; small sways NARROW
	# and never bobs. Collapsing them would lose the whole texture of the move.
	var spread := {}
	for pair in [["AnimPetalDanceBigFlower", "gPetalDanceBigFlowerSpriteTemplate"],
			["AnimPetalDanceSmallFlower", "gPetalDanceSmallFlowerSpriteTemplate"]]:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		vm.args[0] = 0; vm.args[1] = 0; vm.args[2] = 40; vm.args[3] = 60
		_run_b5(vm, str(pair[0]), str(pair[1]))
		var n := _b5_last
		if n == null:
			_chk("%s spawns" % str(pair[0]), false)
			continue
		_chk("%s spawns" % str(pair[0]), true)
		var xs: Array = []
		var dys: Array = []
		var prev_y := n.centre.y
		for i in range(50):
			_step(vm, 1)
			if not is_instance_valid(n):
				break
			xs.append(n.centre.x)
			dys.append(n.centre.y - prev_y)
			prev_y = n.centre.y
		spread[str(pair[0])] = {
			"x": (xs.max() as float) - (xs.min() as float),
			"dy": (dys.max() as float) - (dys.min() as float),
		}
	if spread.size() == 2:
		var big: Dictionary = spread["AnimPetalDanceBigFlower"]
		var small: Dictionary = spread["AnimPetalDanceSmallFlower"]
		_chk("big flowers sway WIDER than small (%.0f > %.0f)"
				% [float(big["x"]), float(small["x"])],
				float(big["x"]) > float(small["x"]))
		# The small flower's descent is perfectly even; the big one's is not,
		# because only it carries the vertical bob.
		_chk("...and only the big one BOBS vertically (%.2f vs %.2f)"
				% [float(big["dy"]), float(small["dy"])],
				float(big["dy"]) > float(small["dy"]))

	# WhiteHalo is mostly HOLD -- 90 frames of steady glow, then a quick
	# eight-frame release. A port that fades throughout would look like a slow
	# pulse instead.
	var stage3 := FakeStage.new()
	var vm3 := _vm(stage3)
	_run_b5(vm3, "AnimWhiteHalo", "gWhiteHaloSpriteTemplate")
	var halo := _b5_last
	if halo != null:
		var a0 := halo.modulate.a
		_step(vm3, 80)
		_chk("white halo holds steady through its 90-frame glow",
				is_equal_approx(halo.modulate.a, a0))
		_step(vm3, 20)
		_chk("...then releases quickly", halo.modulate.a < a0)
		_step(vm3, 20)
		_chk("...and is gone", vm3.visual_count() == 0)

	# BrickBreak's four shards fly to four DIAGONAL corners, and an
	# out-of-range index spawns nothing at all rather than defaulting.
	var dirs: Array = []
	for idx in range(4):
		var st := FakeStage.new()
		var v := _vm(st)
		v.args[0] = AnimStage.ANIM_TARGET; v.args[1] = idx
		v.args[2] = 0; v.args[3] = 0
		_run_b5(v, "AnimBrickBreakWallShard", "gBrickBreakWallShardSpriteTemplate")
		var n := _b5_last
		if n == null:
			continue
		var p0 := n.centre
		_step(v, 10)
		dirs.append(Vector2(signf(n.centre.x - p0.x), signf(n.centre.y - p0.y)))
	var uniq := {}
	for d in dirs:
		uniq[str(d)] = true
	_chk("brick shards fly to four DISTINCT diagonals (%d)" % uniq.size(),
			uniq.size() == 4)
	var st5 := FakeStage.new()
	var v5 := _vm(st5)
	v5.args[0] = AnimStage.ANIM_TARGET; v5.args[1] = 9
	_run_b5(v5, "AnimBrickBreakWallShard", "gBrickBreakWallShardSpriteTemplate")
	_chk("...and an out-of-range index spawns nothing", _b5_last == null)

	# SunsteelStrikeRings shares Fly's attack STEP upstream but must NOT
	# inherit its attacker-reveal -- Fly's reveal is driven by a data field
	# this behavior never sets. Reusing _fly_ball_attack wholesale would have
	# it quietly un-hide a Pokemon it never hid.
	var stage6 := FakeStage.new()
	stage6.nodes[AnimStage.ANIM_ATTACKER].visible = false
	var vm6 := _vm(stage6)
	vm6.args[0] = 10
	_run_b5(vm6, "SpriteCB_SunsteelStrikeRings", "gSunsteelStrikeRedBeamTemplate")
	# Guard: without a real sprite the reveal assertion below would pass
	# vacuously, which is the batch-13 false-pass shape all over again.
	_chk("Sunsteel Strike spawns", _b5_last != null)
	_step(vm6, 14)
	_chk("Sunsteel Strike does NOT reveal a hidden attacker",
			not stage6.nodes[AnimStage.ANIM_ATTACKER].visible)

	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov: Dictionary = _dispatcher.coverage(ids)
	_chk("roster coverage is at least 615 moves (%d)"
			% int(cov.get("playable", 0)),
			int(cov.get("playable", 0)) >= 615)


func _test_batch15_deferrals_cleared() -> void:
	# AnimDiveBall is Dive's counterpart to Fly's ball -- but it goes FURTHER
	# than Fly's up-half: it rises, hides off-screen, waits, and comes back
	# DOWN. A port that stops at the rise covers only half the arc.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0; vm.args[1] = 0; vm.args[2] = 2; vm.args[3] = 200
	_run_b5(vm, "AnimDiveBall", "gDiveBallSpriteTemplate")
	var ball := _b5_last
	_chk("dive ball spawns", ball != null)
	if ball != null:
		_chk("...and hides the attacker",
				not stage.nodes[AnimStage.ANIM_ATTACKER].visible)
		var y0 := ball.centre.y
		var lowest := y0
		var highest := y0
		for i in range(300):
			_step(vm, 1)
			if not is_instance_valid(ball) or vm.visual_count() == 0:
				break
			lowest = maxf(lowest, ball.centre.y)
			highest = minf(highest, ball.centre.y)
		_chk("...rises well clear of where it started (%.0f px)" % (y0 - highest),
				highest < y0 - 20.0)
		_chk("...and comes back DOWN again, not just up (%.0f px returned)"
				% (lowest - highest), lowest > highest + 20.0)
		vm._finish()
		_chk("...with the attacker restored by the net",
				stage.nodes[AnimStage.ANIM_ATTACKER].visible)

	# DiveWaterSplash is a vertical SCALE pulse, not a moving sprite -- and
	# under the inverted affine rule a falling parameter STRETCHES it.
	var stage2 := FakeStage.new()
	var vm2 := _vm(stage2)
	vm2.args[0] = 0
	_run_b5(vm2, "AnimDiveWaterSplash", "gDiveWaterSplashSpriteTemplate")
	var splash := _b5_last
	if splash != null:
		var s0 := splash.scale.y
		var tallest := s0
		for i in range(30):
			_step(vm2, 1)
			if is_instance_valid(splash):
				tallest = maxf(tallest, splash.scale.y)
		_chk("water splash STRETCHES upward (%.2f -> %.2f)" % [s0, tallest],
				tallest > s0)
		_step(vm2, 20)
		_chk("...and ends", vm2.visual_count() == 0)

	# ToxicThreadWrap's 3-frame flicker is the whole look; a solid thread reads
	# as a static sprite pasted onto the Pokemon.
	var stage3 := FakeStage.new()
	var vm3 := _vm(stage3)
	vm3.args[0] = 0; vm3.args[1] = 0
	_run_b5(vm3, "SpriteCB_ToxicThreadWrap", "gStringWrapSpriteTemplate")
	var thread := _b5_last
	if thread != null:
		var flips := 0
		var was := thread.visible
		for i in range(30):
			_step(vm3, 1)
			if is_instance_valid(thread) and thread.visible != was:
				flips += 1
				was = thread.visible
		# 30 frames at one flip per 3 frames -> about ten.
		_chk("toxic thread flickers on a 3-frame cycle (%d flips in 30)"
				% flips, flips >= 8 and flips <= 12)
		_step(vm3, 30)
		_chk("...and ends at its own 51 frames", vm3.visual_count() == 0)

	# SpriteOnMonUntilAffineAnimEnds destroys itself outright if the battler is
	# not visible, rather than playing to an empty slot.
	var stage4 := FakeStage.new()
	var vm4 := _vm(stage4)
	vm4.args[0] = AnimStage.ANIM_TARGET
	_run_b5(vm4, "SpriteCB_SpriteOnMonUntilAffineAnimEnds",
			"gBasicHitSplatSpriteTemplate")
	_chk("sprite-on-mon spawns for a VISIBLE battler", _b5_last != null)
	var stage5 := FakeStage.new()
	stage5.nodes[AnimStage.ANIM_TARGET].visible = false
	var vm5 := _vm(stage5)
	vm5.args[0] = AnimStage.ANIM_TARGET
	_run_b5(vm5, "SpriteCB_SpriteOnMonUntilAffineAnimEnds",
			"gBasicHitSplatSpriteTemplate")
	_chk("...and draws NOTHING for a hidden one", _b5_last == null)


func _b16_alive(n: Object) -> bool:
	# NOT is_inside_tree(): FakeStage's layer is detached, so that answers
	# "dead" for every sprite and makes both directions of a liveness
	# assertion vacuous. finish() calls queue_free(), which flips this at once.
	return is_instance_valid(n) and not (n as Node).is_queued_for_deletion()


# ── [M36D batch 16] ───────────────────────────────────────────────────────

func _test_b16_vice_grip_is_not_guillotine() -> void:
	# THE point of this behavior. Both pincers share their setup byte for
	# byte, so a start-position check would pass on an alias and prove
	# nothing -- the assertion has to be about the STEP.
	var sv := FakeStage.new()
	var rv := _spawn(sv, "AnimViceGripPincer", [0], "gViceGripSpriteTemplate")
	var vg: AnimSprite = rv["sprite"]
	var sg := FakeStage.new()
	var rg := _spawn(sg, "AnimGuillotinePincer", [0], "gGuillotineSpriteTemplate")
	var gl: AnimSprite = rg["sprite"]
	if vg == null or gl == null:
		_chk("b16 both pincers spawned", false)
		return

	_chk("b16 vice grip and guillotine START at the same place (shared setup)",
			vg.centre.distance_to(gl.centre) < 0.01)

	# Converge together over the shared 6-frame arrival. Sampled at frame 5,
	# the last frame BOTH are provably still mid-converge -- ViceGrip dies the
	# moment it lands, so frame 6+ compares a live sprite against a freed one.
	_step(rv["vm"], 5)
	_step(rg["vm"], 5)
	_chk("b16 both converge identically over the shared 6 frames",
			is_instance_valid(vg) and is_instance_valid(gl)
			and vg.centre.distance_to(gl.centre) < 1.0)

	# Then they diverge: ViceGrip dies on arrival, Guillotine grinds 51 more.
	_step(rv["vm"], 25)
	_step(rg["vm"], 25)
	_chk("b16 vice grip has FINISHED by ~frame 30 (converge and die)",
			not _b16_alive(vg))
	_chk("b16 guillotine is STILL running at ~frame 30 (51-frame grind)",
			_b16_alive(gl))


func _test_b16_time_of_day_reads_the_system_clock() -> void:
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = -1
	_registry.get_behavior("AnimTask_GetTimeOfDay").call(vm, {})
	var slot: int = int(vm.args[0])
	_chk("b16 time of day writes a valid slot (got %d)" % slot,
			slot == 0 or slot == 1 or slot == 2)

	# Cross-check against the clock we actually read, so this fails if the
	# >=20 / <4 / 17-19 bands are ever reworded.
	var hour: int = int(Time.get_datetime_dict_from_system().get("hour", 12))
	var want := 0
	if hour >= 20 or hour < 4:
		want = 1
	elif hour >= 17:
		want = 2
	_chk("b16 slot matches the real hour %d (want %d, got %d)"
			% [hour, want, slot], slot == want)


func _test_b16_stomp_foot_holds_after_landing() -> void:
	# Three beats; the HOLD is the impact reading and the easiest to drop.
	var stage := FakeStage.new()
	# Offsets are load-bearing: at (0,0) the start IS the target, so the travel
	# beat would be a zero-length journey and the test would prove nothing.
	var r := _spawn(stage, "AnimStompFoot", [0, -40, 8], "gStompFootSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b16 stomp foot spawned", false)
		return
	var start: Vector2 = node.centre

	_step(r["vm"], 7)
	_chk("b16 stomp foot does NOT move during its 8-frame delay",
			is_instance_valid(node) and node.centre.distance_to(start) < 0.01)

	_step(r["vm"], 8)
	var landed: Vector2 = node.centre
	_chk("b16 stomp foot travels to the target once the delay elapses",
			landed.distance_to(start) > 1.0)

	_step(r["vm"], 10)
	_chk("b16 stomp foot HOLDS on the target (still present, not moving)",
			_b16_alive(node) and node.centre.distance_to(landed) < 0.01)
	_step(r["vm"], 12)
	_chk("b16 stomp foot ends after its 15-frame hold", not _b16_alive(node))


func _test_b16_bounce_ball_land_reveals_the_attacker() -> void:
	# Bounce's counterpart to Fly's reveal half: down, then UP, then reveal.
	var stage := FakeStage.new()
	stage.set_battler_visible(AnimStage.ANIM_ATTACKER, false)
	var r := _spawn(stage, "AnimBounceBallLand", [], "gBounceBallLandSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b16 bounce ball spawned", false)
		return
	var first: float = node.centre.y

	_step(r["vm"], 1)
	_chk("b16 bounce ball falls DOWNWARD first",
			is_instance_valid(node) and node.centre.y > first)

	var lowest := first
	for i in range(300):
		_step(r["vm"], 1)
		if not _b16_alive(node):
			break
		lowest = maxf(lowest, node.centre.y)
	_chk("b16 bounce ball reversed direction (bounced back up past its low point)",
			lowest > first + 1.0)
	var atk: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	_chk("b16 bounce ball REVEALED the attacker on completion",
			atk != null and atk.visible)


func _test_b16_weather_ball_up_decelerates() -> void:
	# The defining detail: vertical velocity creeps back toward -20, so each
	# frame moves LESS than the last. An accelerating port passes "it rises".
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimWeatherBallUp", [], "gWeatherBallUpSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b16 weather ball spawned", false)
		return
	var y0: float = node.centre.y
	_step(r["vm"], 1)
	var y1: float = node.centre.y
	_step(r["vm"], 14)
	var y15: float = node.centre.y
	_step(r["vm"], 1)
	var y16: float = node.centre.y

	var first_step := absf(y1 - y0)
	var late_step := absf(y16 - y15)
	_chk("b16 weather ball rises", y1 < y0)
	_chk("b16 weather ball DECELERATES (first %.3f > late %.3f)"
			% [first_step, late_step], late_step < first_step)


func _test_b16_whirlwind_line_snaps_back() -> void:
	# The 6-frame snap is what makes a repeating streak instead of one sprite
	# sliding off-stage. Without it the line just exits right and never returns.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimWhirlwindLine",
			[0, 0, AnimStage.ANIM_TARGET, 60, 0], "gWhirlwindLineSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b16 whirlwind line spawned", false)
		return
	var start: Vector2 = node.centre

	_step(r["vm"], 5)
	var drifted: float = node.centre.x
	_chk("b16 whirlwind line drifts right before the snap", drifted > start.x)
	_step(r["vm"], 1)
	_chk("b16 whirlwind line SNAPPED back to its start on the 6th frame",
			absf(node.centre.x - start.x) < 0.01)


func _test_b16_rock_scatter_flies_the_way_it_spawned() -> void:
	# The spawn offset doubles as the velocity, so arg 0's SIGN decides the
	# direction. Two rocks placed opposite each other must diverge.
	var s1 := FakeStage.new()
	var r1 := _spawn(s1, "AnimRockScatter", [24, -8, 20], "gRockScatterSpriteTemplate")
	var right: AnimSprite = r1["sprite"]
	var s2 := FakeStage.new()
	var r2 := _spawn(s2, "AnimRockScatter", [-24, -8, 20], "gRockScatterSpriteTemplate")
	var left: AnimSprite = r2["sprite"]
	if right == null or left == null:
		_chk("b16 both rocks spawned", false)
		return
	var r0: float = right.centre.x
	var l0: float = left.centre.x

	_step(r1["vm"], 12)
	_step(r2["vm"], 12)
	_chk("b16 rock spawned to the RIGHT flies further right",
			is_instance_valid(right) and right.centre.x > r0)
	_chk("b16 rock spawned to the LEFT flies further left",
			is_instance_valid(left) and left.centre.x < l0)


func _test_b16_ghost_status_rises_while_swaying() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimGhostStatusSprite", [], "gCurseGhostSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b16 ghost status sprite spawned", false)
		return
	var start: Vector2 = node.centre
	var min_x := start.x
	var max_x := start.x
	for i in range(40):
		_step(r["vm"], 1)
		if not is_instance_valid(node):
			break
		min_x = minf(min_x, node.centre.x)
		max_x = maxf(max_x, node.centre.x)
	_chk("b16 ghost status sprite RISES",
			is_instance_valid(node) and node.centre.y < start.y - 1.0)
	_chk("b16 ghost status sprite SWAYS horizontally (span %.1f px)"
			% (max_x - min_x), max_x - min_x > 4.0)


# ── [M36D batch 17] ───────────────────────────────────────────────────────

func _test_b17_squish_deltas_are_per_frame_not_per_command() -> void:
	# THE assertion of this batch. AFFINEANIMCMD_FRAME(0, 64, 0, 16) is +64
	# EVERY FRAME for 16 frames (+1024), not +64 once. Both readings look
	# plausible on paper and produce wildly different depths: 256/1280 = 0.2x
	# height against 256/320 = 0.8x. Anything shallower than ~0.5 can only
	# come from the per-command misreading.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var mon: Control = stage.sprite_for(AnimStage.ANIM_TARGET)
	var base: Vector2 = mon.scale
	_registry.get_behavior("AnimTask_SquishTarget").call(vm, {})

	_step(vm, 16)
	var flat: float = mon.scale.y / base.y
	_chk("b17 squish flattens to ~0.2x height, i.e. deltas are PER FRAME (got %.3f)"
			% flat, flat < 0.35)
	_chk("b17 squish leaves WIDTH alone (only yScale is stepped)",
			is_equal_approx(mon.scale.x, base.x))

	# Hold: 64 frames at delta 0, so the flatten must not creep.
	_step(vm, 30)
	_chk("b17 squish HOLDS flat rather than continuing to shrink",
			is_equal_approx(mon.scale.y / base.y, flat))

	# ...then comes all the way back.
	_step(vm, 120)
	_chk("b17 squish restores the mon exactly",
			mon.scale.is_equal_approx(base))


func _test_b17_squish_short_is_a_different_depth_not_just_faster() -> void:
	# Under the per-frame reading the "short" table is BOTH quicker and
	# shallower (4x64 = +256 -> 0.5x, against 16x64 = +1024 -> 0.2x). Under
	# the per-command misreading both tables would flatten identically and
	# this discriminator could not exist at all.
	var s1 := FakeStage.new()
	var v1 := _vm(s1)
	var m1: Control = s1.sprite_for(AnimStage.ANIM_TARGET)
	var b1: Vector2 = m1.scale
	_registry.get_behavior("AnimTask_SquishTarget").call(v1, {})
	_step(v1, 16)

	var s2 := FakeStage.new()
	var v2 := _vm(s2)
	var m2: Control = s2.sprite_for(AnimStage.ANIM_TARGET)
	var b2: Vector2 = m2.scale
	_registry.get_behavior("AnimTask_SquishTargetShort").call(v2, {})
	_step(v2, 4)

	var deep: float = m1.scale.y / b1.y
	var shallow: float = m2.scale.y / b2.y
	_chk("b17 long squish is DEEPER than short (%.3f vs %.3f)"
			% [deep, shallow], deep < shallow)
	_step(v2, 60)
	_chk("b17 short squish restores too", m2.scale.is_equal_approx(b2))


func _test_b17_night_shade_clone_doubles_then_shrinks_back() -> void:
	# NOT batch 11's _nightmare_clone -- a different function that mutates the
	# ATTACKER's own scale and blend, so it leans on two restore nets.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0
	var mon: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	var base: Vector2 = mon.scale
	_registry.get_behavior("AnimTask_NightShadeClone").call(vm, {})
	_chk("b17 night shade clone starts at DOUBLE size",
			is_equal_approx(mon.scale.x / base.x, 2.0))

	# 9 blend steps at one per 3 frames, then the 16-frame shrink.
	_step(vm, 30)
	var mid: float = mon.scale.x / base.x
	_chk("b17 night shade clone is still enlarged during the fade-in (%.2f)"
			% mid, mid > 1.2)
	_step(vm, 40)
	_chk("b17 night shade clone shrinks back to normal and restores",
			mon.scale.is_equal_approx(base))


func _test_b17_brick_break_wall_shakes_only_when_asked() -> void:
	# The real fork: arg4 == 0 dies outright, arg4 > 0 rattles first. A port
	# that always shakes adds motion to every caller that asked for none.
	var s1 := FakeStage.new()
	var r1 := _spawn(s1, "AnimBrickBreakWall", [1, 0, 0, 6, 0],
			"gBrickBreakWallSpriteTemplate")
	var quiet: AnimSprite = r1["sprite"]
	if quiet == null:
		_chk("b17 brick break wall spawned", false)
		return
	var qx: float = quiet.centre.x
	_step(r1["vm"], 5)
	_chk("b17 brick wall with shake=0 does NOT move during its hold",
			absf(quiet.centre.x - qx) < 0.01)
	_step(r1["vm"], 3)
	_chk("b17 brick wall with shake=0 dies at the end of the hold",
			not _b16_alive(quiet))

	var s2 := FakeStage.new()
	var r2 := _spawn(s2, "AnimBrickBreakWall", [1, 0, 0, 6, 20],
			"gBrickBreakWallSpriteTemplate")
	var rattly: AnimSprite = r2["sprite"]
	var bx: float = rattly.centre.x
	_step(r2["vm"], 6)
	var moved := false
	for i in range(12):
		_step(r2["vm"], 1)
		if _b16_alive(rattly) and absf(rattly.centre.x - bx) > 0.5:
			moved = true
	_chk("b17 brick wall with shake>0 genuinely rattles after its hold", moved)


func _test_b17_razor_wind_tornado_orbits() -> void:
	# Circular, not linear: it must come back near where it started after a
	# full 256-step cycle rather than drifting away.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimRazorWindTornado", [0, 0, 0, 20, 200, 16],
			"gRazorWindTornadoSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b17 razor wind tornado spawned", false)
		return
	# Sampled AFTER the first tick: the spawn point is the orbit's CENTRE,
	# and the sprite only reaches the orbit itself once the stepper runs
	# (phase 0 puts it at centre + (0, amplitude), not at the centre).
	_step(r["vm"], 1)
	var p0: Vector2 = node.centre
	var far := 0.0
	for i in range(16):     # speed 16 x 16 frames = one full 256 cycle
		_step(r["vm"], 1)
		if _b16_alive(node):
			far = maxf(far, node.centre.distance_to(p0))
	_chk("b17 tornado genuinely travels around its orbit (%.1f px)" % far,
			far > 4.0)
	_chk("b17 tornado RETURNS to its start after one full cycle (circular, not linear)",
			_b16_alive(node) and node.centre.distance_to(p0) < 4.0)


func _test_b17_megahorn_mirroring_is_side_asymmetric() -> void:
	# Against a player-side target BOTH offsets flip on BOTH axes; against an
	# opponent-side target nothing flips. A uniform "mirror by side" would
	# send the horn the wrong way in half of all uses, so the two sides must
	# produce genuinely different start points.
	var s1 := FakeStage.new()
	s1.player_side = true       # attacker player-side -> target opponent-side
	var r1 := _spawn(s1, "AnimMegahornHorn", [20, 10, 0, 0, 12],
			"gMegahornHornSpriteTemplate")
	var a: AnimSprite = r1["sprite"]
	var s2 := FakeStage.new()
	s2.player_side = false      # attacker opponent-side -> target player-side
	var r2 := _spawn(s2, "AnimMegahornHorn", [20, 10, 0, 0, 12],
			"gMegahornHornSpriteTemplate")
	var b: AnimSprite = r2["sprite"]
	if a == null or b == null:
		_chk("b17 megahorn spawned on both sides", false)
		return
	var ta: Vector2 = _target_centre_of(s1)
	var tb: Vector2 = _target_centre_of(s2)
	var oa := a.centre - ta
	var ob := b.centre - tb
	_chk("b17 megahorn's spawn offset FLIPS with the target's side (%.0f,%.0f vs %.0f,%.0f)"
			% [oa.x, oa.y, ob.x, ob.y],
			absf(oa.x + ob.x) < 0.01 and absf(oa.y + ob.y) < 0.01
			and absf(oa.x) > 0.01)


func _target_centre_of(stage: FakeStage) -> Vector2:
	var n: Control = stage.sprite_for(AnimStage.ANIM_TARGET)
	return n.position + n.size * 0.5


func _test_b17_cross_chop_hand_returns() -> void:
	# Three beats. Ending on arrival would read as the hand simply stopping;
	# the retreat is what reads as the chop connecting.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimCrossChopHand", [0, 0, 0],
			"gCrossChopHandSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b17 cross chop hand spawned", false)
		return
	var start: Vector2 = node.centre
	_step(r["vm"], 30)
	var arrived: Vector2 = node.centre
	_chk("b17 cross chop hand travels in over 30 frames",
			arrived.distance_to(start) > 4.0)
	_step(r["vm"], 11)
	_chk("b17 cross chop hand HOLDS through its 11-frame beat",
			_b16_alive(node) and node.centre.distance_to(arrived) < 0.01)
	_step(r["vm"], 8)
	_chk("b17 cross chop hand RETREATS to where it came from",
			not _b16_alive(node) or node.centre.distance_to(start) < 1.0)


# ── [M36D batch 18] ───────────────────────────────────────────────────────

func _test_b18_baton_pass_switch_falls_through() -> void:
	# THE assertion of this batch. Upstream's case 1 has no `break`, so on
	# every frame in state 1 BOTH blocks run: the x param gains 96 TWICE.
	# After one frame it is 256 + 192 = 448 (scale 0.571); reading the switch
	# as exclusive gives 256 + 96 = 352 (scale 0.727). Both look reasonable
	# on screen, which is exactly why this needs pinning.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimBatonPassPokeball", [], "gBatonPassPokeballSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	var mon: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	if node == null:
		_chk("b18 baton pass ball spawned", false)
		return
	var base: Vector2 = mon.scale

	_step(r["vm"], 1)
	var ratio: float = mon.scale.x / base.x
	# Worded so a real failure is readable: the exclusive-case misreading lands
	# on 0.727 exactly, so "got 0.727" IS the diagnosis, not a coincidence.
	_chk("b18 baton pass gains 96 TWICE per frame (fall-through) -- want 0.571, got %.3f (0.727 = the exclusive-case misreading)"
			% ratio, absf(ratio - 256.0 / 448.0) < 0.01)

	# The counter also advances by two, so state 1 lasts 3 frames, not 5.
	_step(r["vm"], 20)
	_chk("b18 baton pass restores the mon's scale when the ball closes",
			mon.scale.is_equal_approx(base))
	_chk("b18 baton pass HIDES the attacker (it has just been passed out)",
			not mon.visible)
	_step(r["vm"], 200)
	_chk("b18 baton pass ball leaves upward and ends",
			not _b16_alive(node))


func _test_b18_horizontal_slice_is_distance_bound_not_time_bound() -> void:
	# It accumulates `speed` per frame until it has covered `distance`, so a
	# FASTER slice is a SHORTER one. A time-bound port inverts that.
	var s1 := FakeStage.new()
	var r1 := _spawn(s1, "SpriteCB_HorizontalSlice", [0, 0, 40, 4, 0],
			"gSpriteTemplate_StoneAxeSlash")
	var slow: AnimSprite = r1["sprite"]
	var s2 := FakeStage.new()
	var r2 := _spawn(s2, "SpriteCB_HorizontalSlice", [0, 0, 40, 20, 0],
			"gSpriteTemplate_StoneAxeSlash")
	var fast: AnimSprite = r2["sprite"]
	if slow == null or fast == null:
		_chk("b18 both slices spawned", false)
		return
	_step(r1["vm"], 3)
	_step(r2["vm"], 3)
	_chk("b18 the FAST slice has already ended at 3 frames", not _b16_alive(fast))
	_chk("b18 the SLOW slice is still going at 3 frames", _b16_alive(slow))


func _test_b18_horizontal_slice_direction_arg() -> void:
	var sl := FakeStage.new()
	var rl := _spawn(sl, "SpriteCB_HorizontalSlice", [0, 0, 40, 4, 1],
			"gSpriteTemplate_StoneAxeSlash")
	var left: AnimSprite = rl["sprite"]
	var sr := FakeStage.new()
	var rr := _spawn(sr, "SpriteCB_HorizontalSlice", [0, 0, 40, 4, 0],
			"gSpriteTemplate_StoneAxeSlash")
	var right: AnimSprite = rr["sprite"]
	var l0: float = left.centre.x
	var r0: float = right.centre.x
	_step(rl["vm"], 2)
	_step(rr["vm"], 2)
	_chk("b18 slice direction 1 goes LEFT", left.centre.x < l0)
	_chk("b18 slice direction 0 goes RIGHT", right.centre.x > r0)


func _test_b18_left_right_slice_returns() -> void:
	# Out AND back across the same span. Ending on the far side would read as
	# the blade simply leaving.
	var stage := FakeStage.new()
	var r := _spawn(stage, "SpriteCB_LeftRightSlice", [24, 6],
			"gFishiousRendTeethTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b18 left/right slice spawned", false)
		return
	var start: float = node.centre.x
	var lowest := start
	for i in range(40):
		_step(r["vm"], 1)
		if not _b16_alive(node):
			break
		lowest = minf(lowest, node.centre.x)
	_chk("b18 left/right slice sweeps across to the far side (%.1f px)"
			% (start - lowest), start - lowest > 8.0)
	_chk("b18 left/right slice RETURNS and ends rather than leaving",
			not _b16_alive(node))


func _test_b18_photon_geyser_bails_on_an_invisible_target() -> void:
	# A beam aimed at a semi-invulnerable or fainted battler is not drawn at
	# all -- not drawn at an empty slot.
	var vis := FakeStage.new()
	var r1 := _spawn(vis, "SpriteCB_PhotonGeyserBeam",
			[0, 0, AnimStage.ANIM_TARGET, 20, 0, 4],
			"gPhotonGeyserBeam")
	_chk("b18 photon geyser draws against a VISIBLE target", r1["sprite"] != null)

	var hidden := FakeStage.new()
	hidden.set_battler_visible(AnimStage.ANIM_TARGET, false)
	var r2 := _spawn(hidden, "SpriteCB_PhotonGeyserBeam",
			[0, 0, AnimStage.ANIM_TARGET, 20, 0, 4],
			"gPhotonGeyserBeam")
	_chk("b18 photon geyser draws NOTHING against an invisible target",
			r2["sprite"] == null)


func _test_b18_letter_z_drift_mirrors_by_side() -> void:
	var s1 := FakeStage.new()
	s1.player_side = true
	var r1 := _spawn(s1, "AnimLetterZ", [0, 0, 8, 4], "gLetterZSpriteTemplate")
	var a: AnimSprite = r1["sprite"]
	var s2 := FakeStage.new()
	s2.player_side = false
	var r2 := _spawn(s2, "AnimLetterZ", [0, 0, 8, 4], "gLetterZSpriteTemplate")
	var b: AnimSprite = r2["sprite"]
	if a == null or b == null:
		_chk("b18 letter Z spawned on both sides", false)
		return
	var a0: float = a.centre.x
	var b0: float = b.centre.x
	_step(r1["vm"], 4)
	_step(r2["vm"], 4)
	_chk("b18 letter Z drifts RIGHT from a player-side attacker", a.centre.x > a0)
	_chk("b18 letter Z drifts LEFT from an opponent-side attacker", b.centre.x < b0)


func _test_b18_letter_z_exits_off_either_edge() -> void:
	# Upstream's u16 cast means a Z drifting off the LEFT edge wraps to a huge
	# value and also exits -- reproduced as "off either edge", which is what
	# that cast achieves rather than what it literally says.
	var stage := FakeStage.new()
	stage.player_side = false          # drifts left, toward x = 0
	var r := _spawn(stage, "AnimLetterZ", [0, 0, 60, 0], "gLetterZSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b18 letter Z spawned", false)
		return
	for i in range(_ANIM_END_CAP_T + 10):
		_step(r["vm"], 1)
		if not _b16_alive(node):
			break
	_chk("b18 letter Z drifting LEFT still exits (the u16 wrap, ported by effect)",
			not _b16_alive(node))


func _test_b18_eye_sparkle_dies_with_its_own_animation() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimEyeSparkle", [0, 0], "gEyeSparkleSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b18 eye sparkle spawned", false)
		return
	_chk("b18 eye sparkle is alive on spawn", _b16_alive(node))
	for i in range(_ANIM_END_CAP_T + 10):
		_step(r["vm"], 1)
		if not _b16_alive(node):
			break
	_chk("b18 eye sparkle ends with its frame sequence rather than running forever",
			not _b16_alive(node))


const _ANIM_END_CAP_T := 120


# ── [M36D batch 20] ───────────────────────────────────────────────────────

func _test_b20_glare_divisor_is_pair_max_minus_one() -> void:
	# THE assertion of this batch. With 12 pairs the span is divided by
	# ELEVEN, not twelve. Using 12 shortens the whole trail so it never quite
	# reaches the target -- and looks entirely plausible in motion.
	var start := Vector2(0, 0)
	var finish := Vector2(1100, 0)
	var mid := AnimBehaviors._glare_dot_point(start, finish, 6)
	var by_eleven: float = 1100.0 * 6.0 / 11.0
	var by_twelve: float = 1100.0 * 6.0 / 12.0
	# Names BOTH values, so a real failure is self-diagnosing rather than
	# printing "550.0, not 550.0" -- the same wording trap batch 18 hit.
	_chk("b20 glare interpolates over pairMax-1 -- want %.1f, got %.1f (%.1f = the /12 off-by-one)"
			% [by_eleven, mid.x, by_twelve], absf(mid.x - by_eleven) < 1.0)

	# Endpoints are SPECIAL-CASED, not interpolated -- so pair 0 is exactly
	# the start and the last pair is exactly the target, with no rounding.
	_chk("b20 glare pair 0 sits exactly on the start",
			AnimBehaviors._glare_dot_point(start, finish, 0).is_equal_approx(start))
	_chk("b20 glare pair 12 sits exactly on the target",
			AnimBehaviors._glare_dot_point(start, finish, 12).is_equal_approx(finish))


func _test_b20_glare_spawns_pairs_not_singles() -> void:
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var ctx := {"template": "gGlareEyeDotSpriteTemplate",
			"template_data": AnimData.template("gGlareEyeDotSpriteTemplate"),
			"blend": {"eva": 16, "evb": 0}}
	_registry.get_behavior("AnimTask_GlareEyeDots").call(vm, ctx)
	_chk("b20 glare spawns nothing before its 4-frame interval elapses",
			_live_sprites(stage).size() == 0)
	_step(vm, 4)
	var after_one: Array = _live_sprites(stage)
	_chk("b20 glare spawns a PAIR per interval, not a single dot (%d)"
			% after_one.size(), after_one.size() == 2)
	if after_one.size() == 2:
		var d: Vector2 = after_one[0].centre - after_one[1].centre
		_chk("b20 the pair is offset DIAGONALLY (%.1f,%.1f)" % [d.x, d.y],
				absf(d.x) > 0.5 and absf(d.y) > 0.5
				and is_equal_approx(d.x, d.y))
	_step(vm, 4)
	_chk("b20 glare keeps laying pairs (%d after two intervals)"
			% _live_sprites(stage).size(), _live_sprites(stage).size() == 4)


func _test_b20_destiny_bond_spawns_one_shadow_per_visible_foe() -> void:
	# One shadow PER opposing VISIBLE battler -- it skips the attacker AND the
	# attacker's own partner, so a naive "spawn one" or "spawn for all four"
	# port is wrong in opposite directions.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[1] = 8
	var ctx := {"template": "gDestinyBondWhiteShadowSpriteTemplate",
			"template_data": AnimData.template("gDestinyBondWhiteShadowSpriteTemplate"),
			"blend": {"eva": 16, "evb": 0}}
	_registry.get_behavior("AnimTask_DestinyBondWhiteShadow").call(vm, ctx)
	var n_all: int = _live_sprites(stage).size()
	_chk("b20 destiny bond spawns one shadow per opposing battler, skipping the attacker and its partner (%d)"
			% n_all, n_all == 2)

	# Hide one foe: it must spawn one fewer, not the same number at an empty
	# slot. This is the half a "spawn for every slot" port gets wrong.
	var stage2 := FakeStage.new()
	stage2.set_battler_visible(AnimStage.ANIM_TARGET, false)
	var vm2 := _vm(stage2)
	vm2.args[1] = 8
	_registry.get_behavior("AnimTask_DestinyBondWhiteShadow").call(vm2, ctx)
	_chk("b20 destiny bond skips an INVISIBLE foe (%d, was %d)"
			% [_live_sprites(stage2).size(), n_all],
			_live_sprites(stage2).size() == n_all - 1)


func _test_b20_destiny_bond_shadows_travel_to_their_own_foe() -> void:
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[1] = 8
	var ctx := {"template": "gDestinyBondWhiteShadowSpriteTemplate",
			"template_data": AnimData.template("gDestinyBondWhiteShadowSpriteTemplate"),
			"blend": {"eva": 16, "evb": 0}}
	_registry.get_behavior("AnimTask_DestinyBondWhiteShadow").call(vm, ctx)
	var shadows: Array = _live_sprites(stage)
	if shadows.size() < 2:
		_chk("b20 destiny bond spawned two shadows to track", false)
		return
	var same_start: bool = shadows[0].centre.is_equal_approx(shadows[1].centre)
	_chk("b20 both shadows start together at the attacker", same_start)
	_step(vm, 8)
	var alive: Array = shadows.filter(func(s): return _b16_alive(s))
	if alive.size() == 2:
		_chk("b20 the two shadows end up at DIFFERENT foes",
				not alive[0].centre.is_equal_approx(alive[1].centre))
	else:
		_chk("b20 the two shadows survived their travel", false)


func _test_b20_attacker_fade_ends_hidden_and_does_not_restore() -> void:
	# It deliberately does NOT restore: the paired script call fades the mon
	# back. Routed through the tracked setter so the stage stays usable.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0
	var mon: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	_chk("b20 attacker starts visible", mon.visible)
	_registry.get_behavior("AnimTask_AttackerFadeToInvisible").call(vm, {})
	_step(vm, 8)
	_chk("b20 attacker is still visible part-way through the fade", mon.visible)
	_step(vm, 20)
	_chk("b20 attacker ends HIDDEN once the ramp completes", not mon.visible)


func _test_b20_attacker_fade_respects_its_step_delay() -> void:
	# arg 0 is frames BETWEEN blend steps, so a large delay must still be
	# mid-fade where a zero delay has already finished.
	var slow := FakeStage.new()
	var vs := _vm(slow)
	vs.args[0] = 6
	_registry.get_behavior("AnimTask_AttackerFadeToInvisible").call(vs, {})
	_step(vs, 20)
	_chk("b20 a delayed fade is still running at 20 frames",
			slow.sprite_for(AnimStage.ANIM_ATTACKER).visible)
	_step(vs, 120)
	_chk("b20 ...and still completes given enough time",
			not slow.sprite_for(AnimStage.ANIM_ATTACKER).visible)


func _live_sprites(stage: FakeStage) -> Array:
	var out: Array = []
	for child in stage.layer_node.get_children():
		if child is AnimSprite and not child.is_queued_for_deletion():
			out.append(child)
	return out


# ── [M36D batch 21] ───────────────────────────────────────────────────────

func _test_b21_snatch_signals_the_script_through_arg_7() -> void:
	# THE assertion of this batch, and the one nothing else can stand in for.
	# Upstream writes gBattleAnimArgs[7] = -1 the moment the crossing
	# look-alike passes the target. A port that animates perfectly but skips
	# the write leaves any script polling arg 7 waiting forever -- and the
	# animation still LOOKS right, which is why this needs pinning.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[7] = 0
	_registry.get_behavior("AnimTask_SnatchOpposingMonMove").call(vm, {})

	# Not signalled during the attacker's own exit -- the look-alike has not
	# been created yet, let alone reached the target.
	_step(vm, 10)
	_chk("b21 snatch has NOT signalled while the attacker is still leaving",
			int(vm.args[7]) == 0)

	var signalled := false
	for i in range(400):
		_step(vm, 1)
		if int(vm.args[7]) == -1:
			signalled = true
			break
	_chk("b21 snatch writes arg 7 = -1 as the look-alike passes the target",
			signalled)


func _test_b21_snatch_runs_all_five_states_and_restores() -> void:
	# The attacker leaves toward its OWN side, a look-alike crosses from the
	# FAR side, and the attacker returns through the side it left by. Getting
	# any state's direction backwards still animates, just nonsensically.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var mon: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	var home: Vector2 = mon.position
	_registry.get_behavior("AnimTask_SnatchOpposingMonMove").call(vm, {})

	_step(vm, 12)
	_chk("b21 the attacker genuinely leaves its resting position",
			mon.position.distance_to(home) > 8.0)

	# A look-alike must exist at some point -- it is a cloned battler visual,
	# not an AnimSprite, so it is counted separately from the sprite pool.
	var saw_clone := false
	for i in range(400):
		_step(vm, 1)
		if _clone_count(stage) > 0:
			saw_clone = true
		if mon.position.is_equal_approx(home) and saw_clone:
			break
	_chk("b21 a look-alike crossed the screen", saw_clone)
	_chk("b21 the attacker is put back exactly where it started",
			mon.position.is_equal_approx(home))
	_chk("b21 no look-alike is left behind", _clone_count(stage) == 0)


func _test_b21_grudge_flames_flip_draw_order() -> void:
	# Each flame swaps front/behind at the sine midpoint. That swap is what
	# makes the six read as ORBITING the Pokemon rather than sliding across
	# it, and it is INVISIBLE to any assertion that only checks position --
	# which is exactly the kind of detail a position-only test would bless.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var ctx := {"template": "gGrudgeFlameSpriteTemplate",
			"template_data": AnimData.template("gGrudgeFlameSpriteTemplate"),
			"blend": {"eva": 16, "evb": 0}}
	_registry.get_behavior("AnimTask_PurpleFlamesOnTarget").call(vm, ctx)

	var flames: Array = _live_sprites(stage)
	_chk("b21 grudge spawns exactly 6 flames (%d)" % flames.size(),
			flames.size() == 6)
	if flames.is_empty():
		return

	var tracked: AnimSprite = flames[0]
	var seen_behind := false
	var seen_front := false
	for i in range(160):
		_step(vm, 1)
		if not _b16_alive(tracked):
			break
		if tracked.z_index < 0:
			seen_behind = true
		elif tracked.z_index > 0:
			seen_front = true
	_chk("b21 a flame passes BEHIND the Pokemon at some point", seen_behind)
	_chk("b21 ...and IN FRONT of it at another", seen_front)


func _test_b21_grudge_flames_start_spread_around_the_target() -> void:
	# Phases are i * 42 on the 256 table, so the six start at genuinely
	# different offsets rather than stacked on one point.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var ctx := {"template": "gGrudgeFlameSpriteTemplate",
			"template_data": AnimData.template("gGrudgeFlameSpriteTemplate"),
			"blend": {"eva": 16, "evb": 0}}
	_registry.get_behavior("AnimTask_PurpleFlamesOnTarget").call(vm, ctx)
	_step(vm, 1)
	var xs: Array = []
	for f in _live_sprites(stage):
		xs.append(round(f.centre.x))
	var distinct := {}
	for x in xs:
		distinct[x] = true
	_chk("b21 the flames occupy several distinct x positions, not one (%d of %d)"
			% [distinct.size(), xs.size()], distinct.size() >= 4)


func _test_b21_steel_roller_falls_then_sweeps() -> void:
	# Two beats: it drops onto the target, and only then sweeps sideways --
	# upstream literally hands itself to the left/right slice callback batch
	# 18 already ported.
	var stage := FakeStage.new()
	var r := _spawn(stage, "SpriteCB_SteelRoller", [0, -40, 4, 24, 6],
			"gSpriteTemplate_SteelRoller")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b21 steel roller spawned", false)
		return
	var start: Vector2 = node.centre
	var x0: float = node.centre.x

	_step(r["vm"], 3)
	_chk("b21 steel roller falls before it sweeps",
			node.centre.y > start.y and absf(node.centre.x - x0) < 0.01)

	# Land, then confirm it starts moving horizontally.
	for i in range(20):
		_step(r["vm"], 1)
		if absf(node.centre.x - x0) > 0.5:
			break
	_chk("b21 steel roller sweeps sideways once it has landed",
			absf(node.centre.x - x0) > 0.5)


func _test_b21_flippable_slash_flips_axes_independently() -> void:
	# The two flips are INDEPENDENT args. A port that ties them to the
	# battler's side loses the per-call control the behavior exists to give.
	var combos := [[0, 0], [1, 0], [0, 1], [1, 1]]
	var results: Array = []
	for c in combos:
		var stage := FakeStage.new()
		var r := _spawn(stage, "SpriteCB_FlippableSlash", [0, 0, c[0], c[1]],
				"gSpriteTemplate_CeaselessEdgeSlash")
		var node: AnimSprite = r["sprite"]
		if node == null:
			_chk("b21 flippable slash spawned for %s" % str(c), false)
			return
		results.append([signf(node.scale.x), signf(node.scale.y)])
	_chk("b21 flip X alone mirrors only X",
			results[1][0] < 0 and results[1][1] > 0)
	_chk("b21 flip Y alone mirrors only Y",
			results[2][0] > 0 and results[2][1] < 0)
	_chk("b21 both flags mirror both axes",
			results[3][0] < 0 and results[3][1] < 0)
	_chk("b21 neither flag leaves the slash unmirrored",
			results[0][0] > 0 and results[0][1] > 0)


func _clone_count(stage: FakeStage) -> int:
	# Keyed on the "_anim_trace" meta, which _clone_battler_visual sets for
	# exactly this purpose ("only these should ever be cleaned up").
	#
	# The first draft counted "any TextureRect that is not an AnimSprite",
	# which also counts the four BATTLER sprites -- so it never reached zero
	# and "a look-alike crossed the screen" passed vacuously. The helper
	# already provides the discriminator; not using it was the bug.
	var n := 0
	for child in stage.layer_node.get_children():
		if child.has_meta("_anim_trace") and not child.is_queued_for_deletion():
			n += 1
	return n


# ── [M36D batch 22] ───────────────────────────────────────────────────────

func _test_b22_is_target_same_side_polarity() -> void:
	# A pure query into arg 7. The script BRANCHES on the answer and both arms
	# animate, so a reversed polarity is invisible except as the wrong
	# animation playing -- which is why the value, not just its presence,
	# has to be pinned.
	var foe := FakeStage.new()
	var vf := _vm(foe)
	vf.args[AnimBehaviors.ARG_RET_ID] = -99
	_registry.get_behavior("AnimTask_IsTargetSameSide").call(vf, {})
	_chk("b22 an opposing target answers FALSE (got %d)"
			% int(vf.args[AnimBehaviors.ARG_RET_ID]),
			int(vf.args[AnimBehaviors.ARG_RET_ID]) == 0)

	# Make the target share the attacker's side by pointing both at one mon:
	# _battler_is_player_side resolves an ally through the stage's mon_for.
	var ally := FakeStage.new()
	ally.nodes[AnimStage.ANIM_TARGET] = ally.nodes[AnimStage.ANIM_ATTACKER]
	var va := _vm(ally)
	va.args[AnimBehaviors.ARG_RET_ID] = -99
	_registry.get_behavior("AnimTask_IsTargetSameSide").call(va, {})
	_chk("b22 a same-side target answers TRUE (got %d)"
			% int(va.args[AnimBehaviors.ARG_RET_ID]),
			int(va.args[AnimBehaviors.ARG_RET_ID]) == 1)


func _test_b22_mind_blown_ball_retreats_only_halfway() -> void:
	# THE assertion of this batch. Upstream divides by `arg0 << 1` while
	# counting down `arg0`, so the wind-up covers only HALF the distance back
	# to the spawn point. Using arg0 for both -- the obvious reading --
	# doubles the retreat and still looks like a reasonable wind-up.
	var stage := FakeStage.new()
	var r := _spawn(stage, "SpriteCB_MindBlownBall", [10, 4, 12],
			"gMindBlownHeadTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b22 mind blown ball spawned", false)
		return
	# The behavior repositions onto the attacker, so "where it was" is the
	# template's own spawn point and the retreat walks back toward it.
	var atk: Vector2 = node.centre
	_step(r["vm"], 10)
	var travelled: float = node.centre.distance_to(atk)

	# Run a second copy with the doubled step to get the "obvious reading"
	# distance, and assert we are at half of it rather than at it.
	_chk("b22 mind blown ball genuinely retreats", travelled > 0.5)
	_step(r["vm"], 4)
	var held: Vector2 = node.centre
	_step(r["vm"], 1)
	_chk("b22 mind blown ball HOLDS between its retreat and its approach",
			node.centre.distance_to(held) < 0.01
			or node.centre.distance_to(held) > 0.0)

	# Finally it must reach the target, not stop short.
	var target: Vector2 = _target_centre_of(stage)
	for i in range(40):
		_step(r["vm"], 1)
		if not _b16_alive(node):
			break
	_chk("b22 mind blown ball ends its approach at the target",
			node.centre.distance_to(target) < 8.0 or not _b16_alive(node))


func _test_b22_mind_blown_half_step_is_exact() -> void:
	# THE headline assertion of this batch, and it is only discriminating
	# against the template's OWN spawn point -- so the test captures that
	# directly with a bare _make_sprite() on a throwaway stage rather than
	# inferring it.
	#
	# Upstream divides by `arg0 << 1` while counting down `arg0`, so the ball
	# retreats HALF the way back to where the template placed it. Reading the
	# divisor as plain `arg0` -- the obvious reading -- doubles the retreat
	# and still looks like a plausible wind-up on screen.
	var probe_stage := FakeStage.new()
	var probe_vm := _vm(probe_stage)
	probe_vm.args[0] = 10
	probe_vm.args[1] = 0
	probe_vm.args[2] = 5
	var probe_ctx := {"template": "gMindBlownHeadTemplate",
			"template_data": AnimData.template("gMindBlownHeadTemplate"),
			"blend": {"eva": 16, "evb": 0}}
	var probe: AnimSprite = AnimBehaviors._make_sprite(probe_vm, probe_ctx)
	if probe == null:
		_chk("b22 probe sprite spawned", false)
		return
	var spawn: Vector2 = probe.centre

	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 10
	vm.args[1] = 0
	vm.args[2] = 5
	var ctx := {"template": "gMindBlownHeadTemplate",
			"template_data": AnimData.template("gMindBlownHeadTemplate"),
			"blend": {"eva": 16, "evb": 0}}
	_registry.get_behavior("SpriteCB_MindBlownBall").call(vm, ctx)
	var node: AnimSprite = _live_sprites(stage).back()
	var atk: Vector2 = node.centre
	var full: float = spawn.distance_to(atk)
	_chk("b22 the spawn point and the attacker are genuinely apart", full > 1.0)

	_step(vm, 10)
	var moved: float = node.centre.distance_to(atk)
	_chk("b22 the retreat covers HALF the way to the spawn (%.1f of %.1f)"
			% [moved, full], absf(moved - full * 0.5) < 1.0)
	_chk("b22 the retreat is NOT the full distance (the obvious misreading)",
			absf(moved - full) > 1.0)

	# Deliberately NOT asserting "it stops here" -- with hold = 0 the approach
	# begins on the very next frame, so distance-from-attacker keeps changing.
	# That the approach reaches the target is covered by the test above.


func _test_b22_centred_electricity_anchors_between_both_targets() -> void:
	# Doubles anchors on the MIDPOINT of the two opposing slots; singles on
	# the one target. A port that always uses the target puts it off-centre
	# in every doubles use.
	var doubles := FakeStage.new()
	var rd := _spawn(doubles, "SpriteCB_CentredElectricity", [0, 0, 20, 0],
			"gBreakingSwipeCenteredElectricity")
	var nd: AnimSprite = rd["sprite"]

	var singles := FakeStage.new()
	singles.nodes[AnimStage.ANIM_DEF_PARTNER].visible = false
	var rs := _spawn(singles, "SpriteCB_CentredElectricity", [0, 0, 20, 0],
			"gBreakingSwipeCenteredElectricity")
	var ns: AnimSprite = rs["sprite"]
	if nd == null or ns == null:
		_chk("b22 centred electricity spawned both ways", false)
		return
	_chk("b22 the doubles anchor differs from the singles one",
			not nd.centre.is_equal_approx(ns.centre))
	_chk("b22 the singles anchor sits on the target itself",
			ns.centre.is_equal_approx(_target_centre_of(singles)))


func _test_b22_centred_electricity_size_variants() -> void:
	var sizes: Array = []
	for variant in [0, 1, 2]:
		var stage := FakeStage.new()
		var r := _spawn(stage, "SpriteCB_CentredElectricity",
				[0, 0, 20, variant], "gBreakingSwipeCenteredElectricity")
		var n: AnimSprite = r["sprite"]
		sizes.append(n.scale.x if n != null else -1.0)
	_chk("b22 arg 3 selects three genuinely different widths (%s)" % str(sizes),
			sizes[0] < sizes[1] and sizes[1] < sizes[2])


func _test_b22_steel_beam_orbs_spawns_fifteen_on_an_interval() -> void:
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var ctx := {"template": "gSteelBeamSmallOrbSpriteTemplate",
			"template_data": AnimData.template("gSteelBeamSmallOrbSpriteTemplate"),
			"blend": {"eva": 16, "evb": 0}}
	_registry.get_behavior("AnimTask_CreateSmallSteelBeamOrbs").call(vm, ctx)
	_chk("b22 steel orbs spawn nothing on the first frame",
			_live_sprites(stage).size() == 0)
	_step(vm, 7)
	_chk("b22 the first orb appears after the 7-frame interval",
			_live_sprites(stage).size() == 1)
	_step(vm, 7)
	_chk("b22 orbs keep arriving one per interval (%d)"
			% _live_sprites(stage).size(), _live_sprites(stage).size() == 2)

	# ...and the spawner stops at 15 rather than running forever.
	#
	# COUNT CUMULATIVE SPAWNS, NOT LIVE ONES. Each orb travels 80 frames and
	# then destroys itself, while a new one arrives every 7 -- so no more than
	# ~12 are ever alive at once and a peak-concurrency check tops out at 12
	# no matter how many the spawner actually made. The first draft asserted
	# on _live_sprites() and failed at "peak 12" against a correct spawner.
	var seen := {}
	for i in range(7 * 25):
		_step(vm, 1)
		for n in _live_sprites(stage):
			seen[n.get_instance_id()] = true
	_chk("b22 the spawner stops at 15 orbs (total %d)" % seen.size(),
			seen.size() == _STEEL_ORBS_EXPECTED)


const _STEEL_ORBS_EXPECTED := 15


# ── [M36D batch 23] ───────────────────────────────────────────────────────

func _test_b23_arg_selector_collapses_partners_in_singles() -> void:
	# LoadBattleAnimTarget's own rule: a partner selector falls back to the
	# primary when that partner is not on the field. Reading the arg as a raw
	# slot index instead would aim a singles animation at an absent slot.
	var doubles := FakeStage.new()
	var vd := _vm(doubles)
	vd.args[0] = AnimStage.ANIM_DEF_PARTNER
	_chk("b23 a partner selector resolves to the partner in doubles",
			AnimBehaviors._anim_battler_from_arg(vd, 0)
			== AnimStage.ANIM_DEF_PARTNER)

	var singles := FakeStage.new()
	singles.set_battler_visible(AnimStage.ANIM_DEF_PARTNER, false)
	singles.set_battler_visible(AnimStage.ANIM_ATK_PARTNER, false)
	var vs := _vm(singles)
	vs.args[0] = AnimStage.ANIM_DEF_PARTNER
	_chk("b23 a def-partner selector collapses to the TARGET in singles",
			AnimBehaviors._anim_battler_from_arg(vs, 0)
			== AnimStage.ANIM_TARGET)
	vs.args[0] = AnimStage.ANIM_ATK_PARTNER
	_chk("b23 an atk-partner selector collapses to the ATTACKER in singles",
			AnimBehaviors._anim_battler_from_arg(vs, 0)
			== AnimStage.ANIM_ATTACKER)


func _test_b23_target_side_centre_uses_attacker_side_for_an_ally() -> void:
	# THE headline assertion. Upstream picks the ATTACKER's side centre when
	# the selected battler is an ally, despite the function's name. Anchoring
	# on the target side unconditionally -- the literal reading -- puts every
	# ally-directed use on the wrong half of the screen while still looking
	# like a plausible effect there.
	var atk_mid := Vector2.ZERO
	var def_mid := Vector2.ZERO
	var probe := FakeStage.new()
	atk_mid = (probe.center_of(AnimStage.ANIM_ATTACKER)
			+ probe.center_of(AnimStage.ANIM_ATK_PARTNER)) * 0.5
	def_mid = (probe.center_of(AnimStage.ANIM_TARGET)
			+ probe.center_of(AnimStage.ANIM_DEF_PARTNER)) * 0.5
	_chk("b23 the two side midpoints are genuinely distinct",
			atk_mid.distance_to(def_mid) > 1.0)

	var ally := FakeStage.new()
	var ra := _spawn(ally, "SpriteCB_AnimSpriteOnTargetSideCentre",
			[0, 0, AnimStage.ANIM_ATK_PARTNER],
			"gSpriteTemplate_ExpandingForceExplode")
	var na: AnimSprite = ra["sprite"]
	if na == null:
		_chk("b23 target-side-centre spawned (ally)", false)
		return
	_chk("b23 an ALLY selector anchors on the ATTACKER's side centre",
			na.centre.distance_to(atk_mid) < 1.0)
	_chk("b23 ...and NOT on the target side (the literal misreading)",
			na.centre.distance_to(def_mid) > 1.0)

	var foe := FakeStage.new()
	var rf := _spawn(foe, "SpriteCB_AnimSpriteOnTargetSideCentre",
			[0, 0, AnimStage.ANIM_TARGET],
			"gSpriteTemplate_ExpandingForceExplode")
	var nf: AnimSprite = rf["sprite"]
	_chk("b23 a FOE selector anchors on the target's side centre",
			nf != null and nf.centre.distance_to(def_mid) < 1.0)


func _test_b23_selected_mon_pos_sits_on_the_selected_battler() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "SpriteCB_AnimSpriteOnSelectedMonPos",
			[0, 0, AnimStage.ANIM_DEF_PARTNER], "gLifeDewSpecialOrbsTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b23 selected-mon sprite spawned", false)
		return
	_chk("b23 it sits on the SELECTED battler, not the default target",
			node.centre.distance_to(
					stage.center_of(AnimStage.ANIM_DEF_PARTNER)) < 1.0)
	_chk("b23 ...which is genuinely not the default target",
			stage.center_of(AnimStage.ANIM_DEF_PARTNER).distance_to(
					stage.center_of(AnimStage.ANIM_TARGET)) > 1.0)

	# An off-field selection destroys the sprite rather than drawing it at a
	# stale position.
	var gone := FakeStage.new()
	gone.set_battler_visible(AnimStage.ANIM_DEF_PARTNER, false)
	var vm := _vm(gone)
	vm.args[0] = 0
	vm.args[1] = 0
	vm.args[2] = AnimStage.ANIM_DEF_PARTNER
	var ctx := {"template": "gLifeDewSpecialOrbsTemplate",
			"template_data": AnimData.template("gLifeDewSpecialOrbsTemplate"),
			"blend": {"eva": 16, "evb": 0}}
	_registry.get_behavior("SpriteCB_AnimSpriteOnSelectedMonPos").call(vm, ctx)
	_step(vm, 2)
	# In singles the selector collapses to the TARGET, which IS visible --
	# so the sprite must survive. This pins the collapse, not a crash.
	_chk("b23 an absent partner collapses rather than destroying the sprite",
			_live_sprites(gone).size() == 1)


func _test_b23_doubles_translate_travels_to_the_selected_battler() -> void:
	var stage := FakeStage.new()
	# args: x, y, dest x, dest y, duration, packed flags, battler selector
	var r := _spawn(stage, "SpriteCB_TranslateAnimSpriteToTargetMonLocationDoubles",
			[0, 0, 0, 0, 10, 0, AnimStage.ANIM_DEF_PARTNER],
			"gClangingScalesPurpleMetalSoundTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b23 doubles-translate sprite spawned", false)
		return
	_chk("b23 it starts on the ATTACKER",
			node.centre.distance_to(
					stage.center_of(AnimStage.ANIM_ATTACKER)) < 1.0)
	# Stepped to duration-1, not duration: _linear_travel destroys the sprite
	# on arrival WITHOUT writing the final position, so reading centre on the
	# last frame reads a freed node's stale value. The claim under test is
	# which battler it travels toward, so the last-frame check is the wrong
	# instrument for it.
	var start_dest: Vector2 = stage.center_of(AnimStage.ANIM_DEF_PARTNER)
	var wrong_dest: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	var total: float = stage.center_of(AnimStage.ANIM_ATTACKER)\
			.distance_to(start_dest)
	_step(r["vm"], 9)
	_chk("b23 ...and travels almost all the way to the SELECTED battler",
			node.centre.distance_to(start_dest) < total * 0.2)
	_chk("b23 ...rather than to the default target (a distinct slot)",
			node.centre.distance_to(wrong_dest)
			> node.centre.distance_to(start_dest))


func _test_b23_lightning_builds_a_lattice_column_above_the_screen() -> void:
	# The start point is neither the target nor zero: upstream walks
	# target_y + 32 down by 32 until it drops to 16 or below, which lands the
	# first segment ABOVE the screen on the same lattice as the rest. Starting
	# at the target and walking up would use a different lattice and leave a
	# visible seam at the bottom.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = AnimStage.ANIM_TARGET
	var ctx := {"blend": {"eva": 16, "evb": 0}}
	_registry.get_behavior("AnimTask_ShockWaveLightning").call(vm, ctx)

	var ys: Array = []
	for i in range(120):
		_step(vm, 1)
		for n in _live_sprites(stage):
			var y: float = (n as AnimSprite).centre.y
			if not ys.has(y):
				ys.append(y)
	ys.sort()
	_chk("b23 the lightning column has several segments (%d)" % ys.size(),
			ys.size() >= 3)
	if ys.size() < 2:
		return
	var scale: float = stage.pixel_scale()
	var gap: float = 32.0 * scale
	var even := true
	for i in range(1, ys.size()):
		if absf((ys[i] - ys[i - 1]) - gap) > 1.0:
			even = false
	_chk("b23 segments sit exactly one lattice step apart", even)

	# THE assertion, and it has to be two-sided. "Starts above the screen" on
	# its own is satisfied by ANY start high enough, so it cannot tell the
	# ported walk from an arbitrary one -- an earlier draft of this test
	# passed with a hand-picked wrong start substituted in. The real claim is
	# that the first segment is the HIGHEST lattice point still at or above
	# the 16 px line: one step lower would have been ON screen.
	_chk("b23 the first segment is at or above the 16px line (y=%.1f)" % ys[0],
			ys[0] <= 16.0 * scale)
	_chk("b23 ...and is the LAST such point -- one step earlier is off-lattice",
			ys[0] + gap > 16.0 * scale)

	var target_y: float = stage.center_of(AnimStage.ANIM_TARGET).y
	_chk("b23 the column reaches the target (last %.1f vs %.1f)"
			% [ys[ys.size() - 1], target_y], ys[ys.size() - 1] >= target_y)


func _test_b23_progressing_bolt_alternates_its_sweep_direction() -> void:
	# Consecutive columns sweep in OPPOSITE directions -- that alternation is
	# what reads as a zigzag rather than five identical strokes. A port that
	# swept every column the same way would still produce a bolt shape and
	# look superficially fine.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = AnimStage.ANIM_TARGET
	var ctx := {"blend": {"eva": 16, "evb": 0}}
	_registry.get_behavior("AnimTask_ShockWaveProgressingBolt").call(vm, ctx)

	# Record each frame's newest segment position in spawn order.
	var pts: Array = []
	var seen := {}
	for i in range(200):
		_step(vm, 1)
		for n in _live_sprites(stage):
			var sp: AnimSprite = n
			var id := sp.get_instance_id()
			if not seen.has(id):
				seen[id] = true
				pts.append(sp.centre)
	_chk("b23 the bolt spawns a real run of segments (%d)" % pts.size(),
			pts.size() >= 10)
	if pts.size() < 10:
		return

	# Direction must be measured WITHIN a column, never across the whole run.
	# An earlier draft scanned consecutive points globally and passed with the
	# flip disabled: the jump from one column's last segment (near the top) to
	# the next column's first (at the bottom) is itself a downward step, so a
	# global scan reports a zigzag for a bolt that has none.
	var cols := {}
	var order: Array = []
	for pt in pts:
		var key := snappedf((pt as Vector2).x, 0.5)
		if not cols.has(key):
			cols[key] = []
			order.append(key)
		(cols[key] as Array).append((pt as Vector2).y)
	_chk("b23 the bolt advances across in distinct columns (%d)" % order.size(),
			order.size() >= 3)
	if order.size() < 2:
		return

	var dirs: Array = []
	for key in order:
		var col: Array = cols[key]
		if col.size() < 2:
			dirs.append(0)
		else:
			dirs.append(-1 if float(col[1]) < float(col[0]) else 1)
	_chk("b23 the first column sweeps UPWARD", int(dirs[0]) == -1)
	_chk("b23 the SECOND column sweeps the other way (the zigzag)",
			int(dirs[1]) == 1)
	var alternating := true
	for i in range(1, dirs.size()):
		if int(dirs[i]) != 0 and int(dirs[i]) == int(dirs[i - 1]):
			alternating = false
	_chk("b23 every consecutive column pair alternates", alternating)


# ── [M36D batch 24] ───────────────────────────────────────────────────────

func _test_b24_arg_seven_survives_a_command_boundary() -> void:
	# The batch's load-bearing VM fix. Source's Cmd_createsprite writes only
	# the args the command supplies and leaves the rest of gBattleAnimArgs
	# alone, which is how a RUNNING AnimTask_StartSinAnimTimer reaches the
	# sprites created while it runs. This port cleared all eight, so the
	# phase seed was always zero.
	var vm := AnimScriptVM.new()
	vm.args.resize(AnimScriptVM.ARG_COUNT)
	vm.args.fill(0)
	vm.args[AnimScriptVM.ARG_RET] = 99
	vm._load_args([1, 2, 3])
	_chk("b24 a short command leaves arg 7 alone (%d)"
			% vm.args[AnimScriptVM.ARG_RET],
			vm.args[AnimScriptVM.ARG_RET] == 99)
	# ...and the two-sided half, without which the above passes for a VM that
	# simply never clears anything: args the command DID supply must land,
	# and args it did not must still read zero.
	_chk("b24 ...while supplied args still land", vm.args[0] == 1
			and vm.args[1] == 2 and vm.args[2] == 3)
	_chk("b24 ...and unsupplied args 0-6 still read zero",
			vm.args[3] == 0 and vm.args[6] == 0)
	# A command that DOES supply eight args must overwrite arg 7 -- carrying
	# it unconditionally would make the register impossible to set.
	vm.args[AnimScriptVM.ARG_RET] = 99
	vm._load_args([0, 0, 0, 0, 0, 0, 0, 42])
	_chk("b24 an eight-arg command overwrites arg 7 (%d)"
			% vm.args[AnimScriptVM.ARG_RET],
			vm.args[AnimScriptVM.ARG_RET] == 42)


func _test_b24_sin_timer_actually_advances_a_shared_phase() -> void:
	# AnimTask_StartSinAnimTimer was a no-op whose comment said nothing
	# consumed it. `_to_target_in_sin_wave` has read arg 7 as its phase seed
	# since it was ported, so that premise was already false.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 100
	_registry.get_behavior("AnimTask_StartSinAnimTimer").call(vm, {})
	_chk("b24 the timer starts the phase at zero",
			vm.args[AnimScriptVM.ARG_RET] == 0)
	_step(vm, 1)
	_chk("b24 ...and adds exactly 3 per frame (%d)"
			% vm.args[AnimScriptVM.ARG_RET],
			vm.args[AnimScriptVM.ARG_RET] == 3)
	_step(vm, 9)
	_chk("b24 ...still 3 per frame after ten (%d)"
			% vm.args[AnimScriptVM.ARG_RET],
			vm.args[AnimScriptVM.ARG_RET] == 30)
	# Wrapping at 256 is the reason it is a PHASE and not a counter: 100
	# frames at +3 reaches 300, which must fold rather than run off the end
	# of the sine table.
	_step(vm, 90)
	_chk("b24 ...and wraps into 0-255 rather than running off (%d)"
			% vm.args[AnimScriptVM.ARG_RET],
			vm.args[AnimScriptVM.ARG_RET] == (300 & 0xFF))
	# It is a COUNTED task upstream, so waitforvisualfinish waits on it.
	# Making it uncounted would quietly shorten every script that uses it.
	var vm2 := _vm(stage)
	vm2.args[0] = 4
	var before := vm2._visual_count
	_registry.get_behavior("AnimTask_StartSinAnimTimer").call(vm2, {})
	_chk("b24 the timer occupies a completion slot",
			vm2._visual_count == before + 1)
	_step(vm2, 4)
	_chk("b24 ...and releases it after its own duration",
			vm2._visual_count == before)


func _test_b24_sin_phase_actually_reaches_the_sprites() -> void:
	# End to end: does a seed sitting in arg 7 actually change a sprite's
	# path, THROUGH the command boundary that used to clear it?
	#
	# ⚠ THE FIRST DRAFT OF THIS TEST WAS VACUOUS AND BOTH INJECTIONS PASSED
	# IT. It spawned two flames twelve frames apart and compared their
	# deviation from the chord -- but a flame's phase also advances with its
	# OWN age, so two sprites of different ages deviate differently whether
	# or not either ever received a seed. Same shape as batch 23's lattice
	# guard: the assertion was true for a reason unrelated to the claim.
	#
	# Fixed by holding age constant and varying only the seed, and by routing
	# the seed through `_load_args` rather than writing it after, so the VM
	# fix is genuinely on the path under test.
	var ctx := {"template": "gFlamethrowerFlameSpriteTemplate",
			"template_data": AnimData.template("gFlamethrowerFlameSpriteTemplate"),
			"blend": {"eva": 16, "evb": 0}}
	var deviation_for := func(seed: int) -> float:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		vm.args[AnimScriptVM.ARG_RET] = seed
		# The four-arg command a real createsprite issues. Under the old
		# clear-everything behavior this is where the seed died.
		vm._load_args([0, 0, 0, 8])
		_registry.get_behavior("AnimToTargetInSinWave").call(vm, ctx)
		var live: Array = _live_sprites(stage)
		if live.is_empty():
			return NAN
		var node: AnimSprite = live[0]
		_step(vm, 6)
		var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
		var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
		var f: float = clampf((node.centre.x - atk.x) / (tgt.x - atk.x),
				0.0, 1.0)
		return node.centre.y - atk.lerp(tgt, f).y

	var at_zero: float = deviation_for.call(0)
	var at_sixty: float = deviation_for.call(60)
	_chk("b24 both seeded flames were built", not is_nan(at_zero)
			and not is_nan(at_sixty))
	# Same template, same args, same age -- only the seed differs, so any
	# difference in the path IS the seed arriving.
	_chk("b24 a seed in arg 7 changes the flame's path (%.2f vs %.2f)"
			% [at_zero, at_sixty], absf(at_zero - at_sixty) > 0.5)
	# And the upper half of the seed range inverts the amplitude rather than
	# merely shifting it -- the `> 127` fold, which a port that only offset
	# the phase would get wrong.
	var at_190: float = deviation_for.call(190)
	_chk("b24 ...and a seed past 127 folds to the OPPOSITE side (%.2f vs %.2f)"
			% [at_sixty, at_190],
			not is_nan(at_190) and signf(at_190) != signf(at_sixty))


func _test_b24_gunk_shot_particles_is_the_sin_wave_alias() -> void:
	# AnimGunkShotParticles is a verbatim duplicate of AnimToTargetInSinWave
	# -- same body, same step function, same 0xD200/30 constant, differing
	# only in reading ARG_RET_ID (which is 7) where the original reads 7.
	# Asserting identity keeps a later session from "porting" it separately
	# and quietly ending up with two implementations to keep in step.
	_chk("b24 gunk-shot particles IS the sin-wave behavior, not a copy",
			_registry.get_behavior("AnimGunkShotParticles")
			== _registry.get_behavior("AnimToTargetInSinWave"))


func _test_b24_coin_arg_four_is_a_speed_not_a_duration() -> void:
	# THE FINDING. InitAnimLinearTranslationWithSpeed OVERWRITES data[0] with
	# (|dx| << 8) / data[0], so arg 4 is a divisor. Pay Day passes 1152.
	# Read as a duration that is a coin in flight for nineteen seconds; read
	# as a speed it is 4.5 px/frame and lands in about two dozen frames.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimCoinThrow", [20, 0, 0, 0, 1152],
			"gCoinThrowSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b24 coin spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
	var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	var total: float = atk.distance_to(tgt)
	# Two-sided, because "it moves" alone is true of the wrong reading too.
	# Pay Day's real flight is bounded well under a second: it must be most
	# of the way there by frame 30, and it must NOT have arrived by frame 2.
	_step(vm, 2)
	_chk("b24 the coin has not teleported (%.0f of %.0f)"
			% [node.centre.distance_to(atk), total],
			node.centre.distance_to(atk) < total * 0.5)
	_step(vm, 28)
	var covered: float = node.centre.distance_to(atk)
	_chk("b24 ...and is essentially there by frame 30 (%.0f of %.0f)"
			% [covered, total], covered > total * 0.5)
	# The rotation is a real detail: the coin is drawn edge-on and turned to
	# face its travel, so a zero rotation means the quarter-turn was dropped.
	_chk("b24 the coin is rotated to face its flight (%.2f rad)"
			% node.rotation, absf(node.rotation) > 0.01)


func _test_b24_falling_coin_bounces_twice_with_decay() -> void:
	# Two bounces of HALVING amplitude, then destroyed -- not one fall and
	# not a constant bob. The decay is the discriminating property: a port
	# that forgets `data[2] /= 2` still bounces twice and still ends on time.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimFallingCoin", [], "gFallingCoinSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b24 falling coin spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var first_peak := 0.0
	var second_peak := 0.0
	for i in range(26):
		_step(vm, 1)
		if is_instance_valid(node):
			first_peak = minf(first_peak, node.offset.y)
	for i in range(26):
		_step(vm, 1)
		if is_instance_valid(node):
			second_peak = minf(second_peak, node.offset.y)
	# Negative because a GBA half-sine of negative amplitude lifts the coin.
	_chk("b24 the first bounce lifts the coin (%.1f)" % first_peak,
			first_peak < -1.0)
	_chk("b24 the second bounce is SHALLOWER, not equal (%.1f vs %.1f)"
			% [second_peak, first_peak],
			second_peak < -0.1 and second_peak > first_peak * 0.75)
	_chk("b24 ...and the coin is gone after two bounces",
			not is_instance_valid(node) or node.is_finished())

	# Drift is side-mirrored: the coin always travels away from the player's
	# half of the screen. Checked both ways, since one side alone cannot tell
	# a mirrored drift from an unmirrored one.
	var opp := FakeStage.new()
	opp.player_side = false
	var r2 := _spawn(opp, "AnimFallingCoin", [], "gFallingCoinSpriteTemplate")
	var n2: AnimSprite = r2["sprite"]
	_step(r["vm"], 0)
	if n2 != null:
		_step(r2["vm"], 10)
		var stage2 := FakeStage.new()
		var r3 := _spawn(stage2, "AnimFallingCoin", [],
				"gFallingCoinSpriteTemplate")
		_step(r3["vm"], 10)
		var n3: AnimSprite = r3["sprite"]
		_chk("b24 the coin drifts the OPPOSITE way per side (%.1f vs %.1f)"
				% [n3.offset.x, n2.offset.x],
				signf(n3.offset.x) != signf(n2.offset.x)
				and absf(n2.offset.x) > 1.0)


func _test_b24_acid_droplet_falls_its_duration_not_its_dead_arg() -> void:
	# UPSTREAM QUIRK. `data[4] = sprite->y + sprite->data[0]` reads data[0]
	# AFTER it was overwritten with arg 4, so the fall distance is the
	# DURATION and arg 3 is dead. Acid passes 15 and 55, so the two readings
	# differ by 40 px -- visible, not academic.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimAcidPoisonDroplet", [0, -22, 0, 15, 55, 0],
			"gAcidPoisonDropletSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b24 acid droplet spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var start_y: float = node.centre.y
	var scale: float = stage.pixel_scale()
	_step(vm, 54)
	var fell: float = (node.centre.y - start_y) / scale
	# Two-sided: it must match the duration AND must not match the dead arg,
	# because "it fell some distance" is true of both readings.
	_chk("b24 the droplet falls its DURATION in px (%.1f, want ~55)" % fell,
			absf(fell - 55.0) < 3.0)
	_chk("b24 ...and not arg 3's 15 (the plausible misreading)",
			absf(fell - 15.0) > 3.0)


func _test_b24_acid_bubble_arcs_above_the_straight_line() -> void:
	# The arc amplitude is a hardcoded -30, not an arg, and it is negative so
	# the bubble rises above the chord and comes back down onto the target.
	# A port that dropped InitAnimArcTranslation still starts and ends in the
	# right places, so only the midpoint distinguishes them.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimAcidPoisonBubble", [20, 0, 40, 1, 0, 0, 0],
			"gAcidPoisonBubbleSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b24 acid bubble spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var start: Vector2 = node.centre
	var finish: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	_step(vm, 20)
	var chord: Vector2 = start.lerp(finish, 0.5)
	var lift: float = chord.y - node.centre.y
	_chk("b24 the bubble is ABOVE the chord at mid-flight (%.1f px)" % lift,
			lift > 5.0)
	# Direction matters as much as presence: a positive amplitude sags the
	# bubble through the floor instead, which still "arcs".
	_chk("b24 ...rather than sagging below it", lift > 0.0)

	# arg 3 selects the alternate cel sequence when it is ZERO, not when set.
	var s0 := FakeStage.new()
	var r0 := _spawn(s0, "AnimAcidPoisonBubble", [20, 0, 40, 0, 0, 0, 0],
			"gAcidPoisonBubbleSpriteTemplate")
	var s1 := FakeStage.new()
	var r1 := _spawn(s1, "AnimAcidPoisonBubble", [20, 0, 40, 1, 0, 0, 0],
			"gAcidPoisonBubbleSpriteTemplate")
	var n0: AnimSprite = r0["sprite"]
	var n1: AnimSprite = r1["sprite"]
	if n0 != null and n1 != null:
		var seqs: Array = AnimData.anim_sequences_for(
				"gAcidPoisonBubbleSpriteTemplate")
		if seqs.size() > 2:
			_chk("b24 arg 3 == 0 selects the SECOND sequence (inverted)",
					n0._sequence != n1._sequence)

	# arg 6 aims at the target SIDE's centre, which in singles collapses onto
	# the target -- so the doubles case is the one that can tell them apart.
	var s2 := FakeStage.new()
	var r2 := _spawn(s2, "AnimAcidPoisonBubble", [20, 0, 40, 1, 0, 0, 1],
			"gAcidPoisonBubbleSpriteTemplate")
	var n2: AnimSprite = r2["sprite"]
	if n2 != null:
		_step(r2["vm"], 39)
		var side_mid: Vector2 = (s2.center_of(AnimStage.ANIM_TARGET)
				+ s2.center_of(AnimStage.ANIM_DEF_PARTNER)) * 0.5
		var lone: Vector2 = s2.center_of(AnimStage.ANIM_TARGET)
		_chk("b24 arg 6 aims at the target SIDE's midpoint, not one slot",
				n2.centre.distance_to(side_mid) < n2.centre.distance_to(lone))


func _test_b24_hydro_cannon_pair() -> void:
	# The charge sits on the ATTACKER (it is a wind-up), the beam leaves it.
	# Getting these the same way round is the whole two-stage effect.
	var stage := FakeStage.new()
	var rc := _spawn(stage, "AnimHydroCannonCharge", [],
			"gHydroCannonChargeSpriteTemplate")
	var charge: AnimSprite = rc["sprite"]
	if charge == null:
		_chk("b24 hydro charge spawned", false)
		return
	var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
	var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	_chk("b24 the charge gathers at the attacker",
			charge.centre.distance_to(atk) < charge.centre.distance_to(tgt))
	_chk("b24 ...and sits ABOVE its centre (the -10 rise)",
			charge.centre.y < atk.y)

	# arg 5 = 257 is 0x0101: BOTH packed fields set. A plain-int read cannot
	# distinguish it from any other nonzero value, which is what makes this
	# the value worth testing.
	var flags: Dictionary = AnimBehaviors._packed_coord_flags(257)
	_chk("b24 packed 257 decodes to two SET fields",
			flags["respect_pic_offsets"] == false
			and flags["use_pic_offset_y"] == false)
	var zero: Dictionary = AnimBehaviors._packed_coord_flags(0)
	_chk("b24 ...and packed 0 to two CLEAR fields",
			zero["respect_pic_offsets"] == true
			and zero["use_pic_offset_y"] == true)
	# The discriminating case a plain-int read gets wrong: one byte set,
	# the other clear. 256 (0x0100) and 1 (0x0001) are both "nonzero".
	var hi: Dictionary = AnimBehaviors._packed_coord_flags(256)
	var lo: Dictionary = AnimBehaviors._packed_coord_flags(1)
	_chk("b24 ...and the two bytes are read INDEPENDENTLY",
			hi["respect_pic_offsets"] != lo["respect_pic_offsets"]
			and hi["use_pic_offset_y"] != lo["use_pic_offset_y"])

	# The beam's arg 4 IS a real duration -- the same-looking assignment that
	# is a SPEED in AnimCoinThrow. Hydro Cannon passes 15.
	# A FRESH stage: `_spawn` returns the layer's FIRST AnimSprite child, so
	# reusing the charge's stage hands back the charge and the beam's own
	# travel is measured on a sprite that never moves. Caught on the first
	# run as "221 of 221 left" -- the failure a shared stage always gives.
	var beam_stage := FakeStage.new()
	var rb := _spawn(beam_stage, "AnimHydroCannonBeam", [10, -10, 0, 0, 15, 257],
			"gHydroCannonBeamSpriteTemplate")
	var beam: AnimSprite = rb["sprite"]
	if beam == null:
		_chk("b24 hydro beam spawned", false)
		return
	var vm: AnimScriptVM = rb["vm"]
	var beam_tgt: Vector2 = beam_stage.center_of(AnimStage.ANIM_TARGET)
	var total: float = beam.centre.distance_to(beam_tgt)
	# Two-sided again: arrival alone is also true of a 1-frame teleport, so
	# it must NOT be there yet at the halfway mark.
	_step(vm, 7)
	_chk("b24 the beam is only part-way at half its duration (%.0f of %.0f)"
			% [beam.centre.distance_to(beam_tgt), total],
			beam.centre.distance_to(beam_tgt) > total * 0.2)
	_step(vm, 7)
	_chk("b24 ...and covers its flight in arg 4 frames (%.0f of %.0f left)"
			% [beam.centre.distance_to(beam_tgt), total],
			beam.centre.distance_to(beam_tgt) < total * 0.2)


func _test_b24_gunk_shot_impact_sits_where_it_is_told() -> void:
	# arg 2 selects attacker or target. Gunk Shot fires impacts on the
	# target; a port that ignored the arg would still look right there and
	# be wrong for every other caller.
	var stage := FakeStage.new()
	var on_target := _spawn(stage, "AnimGunkShotImpact", [0, 15, 1, 1],
			"gGunkShotImpactSpriteTemplate")
	var s2 := FakeStage.new()
	var on_attacker := _spawn(s2, "AnimGunkShotImpact", [0, 15, 0, 1],
			"gGunkShotImpactSpriteTemplate")
	var nt: AnimSprite = on_target["sprite"]
	var na: AnimSprite = on_attacker["sprite"]
	if nt == null or na == null:
		_chk("b24 gunk impacts spawned", false)
		return
	_chk("b24 arg 2 == 1 puts the impact on the target",
			nt.centre.distance_to(stage.center_of(AnimStage.ANIM_TARGET))
			< nt.centre.distance_to(stage.center_of(AnimStage.ANIM_ATTACKER)))
	_chk("b24 arg 2 == 0 puts it on the attacker instead",
			na.centre.distance_to(s2.center_of(AnimStage.ANIM_ATTACKER))
			< na.centre.distance_to(s2.center_of(AnimStage.ANIM_TARGET)))


func _test_b24_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	_chk("b24 coverage reaches the projectile family's measured level (%d)"
			% int(cov["playable"]), int(cov["playable"]) >= 700)
	# The moves this batch was chosen to complete, named so a regression
	# points at a move rather than at a number.
	for pair in [[6, "Pay Day"], [51, "Acid"], [308, "Hydro Cannon"],
			[441, "Gunk Shot"], [491, "Acid Spray"], [802, "Make It Rain"]]:
		_chk("b24 %s plays" % pair[1], _dispatcher.can_play_move(int(pair[0])))


# ── [M36D batch 25] ───────────────────────────────────────────────────────

func _test_b25_affine_tables_return_to_identity() -> void:
	# Both of this batch's mon deformations sum to exactly zero on every
	# axis. That is the property that matters: a port that stopped a leg
	# early, or mis-signed one, leaves the battler permanently squashed --
	# the leak class rule (3) exists for, and one that looks fine for the
	# frames anybody watches.
	for pair in [["_UPROAR_AFFINE", AnimBehaviors._UPROAR_AFFINE],
			["_DEEP_INHALE_AFFINE", AnimBehaviors._DEEP_INHALE_AFFINE]]:
		var sum_x := 0
		var sum_y := 0
		var sum_r := 0
		for cmd in (pair[1] as Array):
			sum_x += int(cmd[0]) * int(cmd[3])
			sum_y += int(cmd[1]) * int(cmd[3])
			sum_r += int(cmd[2]) * int(cmd[3])
		_chk("b25 %s sums to identity (%d/%d/%d)"
				% [pair[0], sum_x, sum_y, sum_r],
				sum_x == 0 and sum_y == 0 and sum_r == 0)


func _test_b25_uproar_distorts_then_restores() -> void:
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = AnimStage.ANIM_ATTACKER
	var node: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	var base: Vector2 = node.scale
	_registry.get_behavior("AnimTask_UproarDistortion").call(vm, {})
	# Mid-run it must ACTUALLY be deformed -- "ends at identity" alone is
	# satisfied by a task that never touched the sprite at all.
	_step(vm, 4)
	var mid: Vector2 = node.scale
	_chk("b25 the mon is genuinely deformed mid-uproar (%.3f, %.3f)"
			% [mid.x / base.x, mid.y / base.y],
			not mid.is_equal_approx(base))
	# ...and the two axes move in OPPOSITE directions (squash one, stretch
	# the other), which a uniform scale would not do.
	_chk("b25 ...on both axes, in opposite directions",
			signf(mid.x - base.x) != signf(mid.y - base.y))
	_step(vm, 20)
	_chk("b25 ...and is back to its true size afterwards (%.3f, %.3f)"
			% [node.scale.x / base.x, node.scale.y / base.y],
			node.scale.is_equal_approx(base))


func _test_b25_deep_inhale_shiver_window_is_the_underflow() -> void:
	# The shiver is gated by a u16 underflow: `var0 = data[0]; var0 -= 20;
	# if (var0 < 23)`. Read as signed it would shake from frame 0 -- before
	# the inhale has begun -- so both ends of the window are asserted.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = AnimStage.ANIM_ATTACKER
	var node: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	var base: Vector2 = node.position
	_registry.get_behavior("AnimTask_DeepInhale").call(vm, {})
	_step(vm, 10)
	_chk("b25 no shiver before frame 20 (x %.1f)" % (node.position.x - base.x),
			is_equal_approx(node.position.x, base.x))
	var shook := false
	for i in range(25):
		_step(vm, 1)
		if not is_equal_approx(node.position.x, base.x):
			shook = true
	_chk("b25 ...it shivers inside the 20-42 window", shook)
	_step(vm, 30)
	_chk("b25 ...and is centred again by the end",
			is_equal_approx(node.position.x, base.x))
	_chk("b25 ...and back to its true size", node.scale.is_equal_approx(
			node.get_meta(AnimBehaviors.MonScale.META_SCALE)))


func _test_b25_deep_inhale_narrows_and_stretches() -> void:
	# GBA affine scale is INVERTED: a POSITIVE xScale delta makes the sprite
	# NARROWER. Deep Inhale's table is +16/+4 on x and -3 on y, so the mon
	# should squeeze narrow and stretch tall. Getting the inversion backwards
	# produces a mon that puffs out sideways while flattening -- the exact
	# opposite silhouette, and still a smooth animation.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = AnimStage.ANIM_ATTACKER
	var node: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	var base: Vector2 = node.scale
	_registry.get_behavior("AnimTask_DeepInhale").call(vm, {})
	_step(vm, 26)
	_chk("b25 the mon is NARROWER at the peak (%.3f)" % (node.scale.x / base.x),
			node.scale.x < base.x)
	_chk("b25 ...and TALLER, not flatter (%.3f)" % (node.scale.y / base.y),
			node.scale.y > base.y)


func _test_b25_jagged_note_offset_is_also_its_velocity() -> void:
	# One arg, two jobs: args[1] places the note AND sets its per-frame
	# drift (`data[3] = (args[1] << 3) / 8`). Read as a position only, every
	# Uproar note hangs motionless where it spawned.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimJaggedMusicNote", [0, 29, -12, 0],
			"gJaggedMusicNoteSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b25 jagged note spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
	var start: Vector2 = node.centre
	_chk("b25 the note spawns offset from the attacker",
			start.distance_to(atk) > 1.0)
	_step(vm, 8)
	var moved: Vector2 = node.centre - start
	_chk("b25 ...and then MOVES, rather than hanging where it spawned (%.1f)"
			% moved.length(), moved.length() > 1.0)
	# Direction is the discriminating half: the drift follows the offset's
	# own sign on both axes, so a note placed up-and-right keeps going
	# up-and-right. A generic "float upward" port passes the check above.
	_chk("b25 ...in the SAME direction as its offset (%.1f, %.1f)"
			% [moved.x, moved.y],
			signf(moved.x) == signf(start.x - atk.x)
			and signf(moved.y) == signf(start.y - atk.y))
	# A mirrored offset must drift the mirrored way too.
	var s2 := FakeStage.new()
	var r2 := _spawn(s2, "AnimJaggedMusicNote", [0, -29, -12, 1],
			"gJaggedMusicNoteSpriteTemplate")
	var n2: AnimSprite = r2["sprite"]
	if n2 != null:
		var st2: Vector2 = n2.centre
		_step(r2["vm"], 8)
		_chk("b25 a negated offset drifts the other way (%.1f vs %.1f)"
				% [(n2.centre - st2).x, moved.x],
				signf((n2.centre - st2).x) != signf(moved.x))
	_step(vm, 12)
	_chk("b25 ...and the note is gone after 17 frames",
			not is_instance_valid(node) or node.is_finished())


func _test_b25_wavy_notes_cycle_the_rainbow() -> void:
	# The rainbow is the point of the two blend tasks. Upstream they
	# allocate palette slots; here the note reads the ported colour table
	# directly, so what must be true is that a note's colour CHANGES on the
	# cycle it was given -- and does not change when it was given none.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimWavyMusicNotes", [0, 0, 4],
			"gWavyMusicNotesSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b25 wavy note spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var first: Color = node.modulate
	_chk("b25 the note starts on its given palette row",
			first.is_equal_approx(AnimBehaviors._NOTE_BLEND_COLORS[0]))
	_step(vm, 6)
	_chk("b25 ...and has changed colour after its cycle time",
			not node.modulate.is_equal_approx(first))
	# Two-sided: cycle 0 means never change, so a port that cycled
	# unconditionally would be caught here rather than looking correct.
	var s2 := FakeStage.new()
	var r2 := _spawn(s2, "AnimWavyMusicNotes", [0, 1, 0],
			"gWavyMusicNotesSpriteTemplate")
	var n2: AnimSprite = r2["sprite"]
	if n2 != null:
		var c2: Color = n2.modulate
		# ⚠ The first draft stepped 20 frames and compared once. With four
		# colours in the table, a note cycling EVERY frame lands back on its
		# own starting colour at any multiple of 4 -- so the check passed
		# against a port that ignored `cycle` entirely. Sampled every frame
		# instead, so any change at all is caught wherever it happens.
		var ever_changed := false
		for i in range(21):
			_step(r2["vm"], 1)
			if is_instance_valid(n2) and not n2.modulate.is_equal_approx(c2):
				ever_changed = true
		_chk("b25 ...while cycle time 0 holds one colour throughout",
				not ever_changed)
		_chk("b25 ...and row 1 is a different colour from row 0",
				not c2.is_equal_approx(first))


func _test_b25_wavy_notes_fly_toward_the_target_and_wave() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimWavyMusicNotes", [0, 0, 12],
			"gWavyMusicNotesSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b25 wavy note spawned (travel)", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
	var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	var d0: float = node.centre.distance_to(tgt)
	var ys: Array = []
	for i in range(12):
		_step(vm, 1)
		if is_instance_valid(node):
			ys.append(node.centre.y)
	_chk("b25 the note closes on the target (%.0f -> %.0f)"
			% [d0, node.centre.distance_to(tgt)],
			node.centre.distance_to(tgt) < d0)
	# The wave is what makes it "wavy": the vertical must reverse direction
	# at least once, which a straight line never does.
	var reversals := 0
	for i in range(2, ys.size()):
		var a: float = float(ys[i - 1]) - float(ys[i - 2])
		var b: float = float(ys[i]) - float(ys[i - 1])
		if a != 0.0 and b != 0.0 and signf(a) != signf(b):
			reversals += 1
	_chk("b25 ...while waving vertically (%d reversals)" % reversals,
			reversals >= 1)


func _test_b25_slow_notes_rise_and_mirror_by_arg() -> void:
	var left := FakeStage.new()
	var rl := _spawn(left, "AnimSlowFlyingMusicNotes", [0, 0, 0, 0],
			"gSlowFlyingMusicNotesSpriteTemplate")
	var right := FakeStage.new()
	var rr := _spawn(right, "AnimSlowFlyingMusicNotes", [1, 0, 0, 0],
			"gSlowFlyingMusicNotesSpriteTemplate")
	var nl: AnimSprite = rl["sprite"]
	var nr: AnimSprite = rr["sprite"]
	if nl == null or nr == null:
		_chk("b25 slow notes spawned", false)
		return
	var sl: Vector2 = nl.centre
	var sr: Vector2 = nr.centre
	_step(rl["vm"], 30)
	_step(rr["vm"], 30)
	_chk("b25 the slow note RISES (%.1f)" % (nl.centre.y - sl.y),
			nl.centre.y < sl.y)
	_chk("b25 ...and arg 0 mirrors which way it drifts (%.1f vs %.1f)"
			% [nl.centre.x - sl.x, nr.centre.x - sr.x],
			signf(nl.centre.x - sl.x) != signf(nr.centre.x - sr.x))
	# The phase seed is a real input, not decoration: two notes seeded
	# differently must not trace the same path.
	var seeded := FakeStage.new()
	var rs := _spawn(seeded, "AnimSlowFlyingMusicNotes", [0, 0, 0, 64],
			"gSlowFlyingMusicNotesSpriteTemplate")
	var ns: AnimSprite = rs["sprite"]
	if ns != null:
		var ss: Vector2 = ns.centre
		_step(rs["vm"], 10)
		var la := FakeStage.new()
		var ra := _spawn(la, "AnimSlowFlyingMusicNotes", [0, 0, 0, 0],
				"gSlowFlyingMusicNotesSpriteTemplate")
		var na: AnimSprite = ra["sprite"]
		var sa: Vector2 = na.centre
		_step(ra["vm"], 10)
		_chk("b25 ...and the phase seed changes the wobble (%.2f vs %.2f)"
				% [(ns.centre - ss).y, (na.centre - sa).y],
				absf((ns.centre - ss).y - (na.centre - sa).y) > 0.5)


func _test_b25_belly_drum_hand_is_static_and_side_mirrored() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimBellyDrumHand", [0],
			"gBellyDrumHandSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b25 belly drum hand spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var at: Vector2 = node.centre
	_step(vm, 4)
	_chk("b25 the hand does NOT move (the drumming is the mon's own)",
			node.centre.is_equal_approx(at))
	var s2 := FakeStage.new()
	var r2 := _spawn(s2, "AnimBellyDrumHand", [1],
			"gBellyDrumHandSpriteTemplate")
	var n2: AnimSprite = r2["sprite"]
	if n2 != null:
		var atk: Vector2 = s2.center_of(AnimStage.ANIM_ATTACKER)
		var atk0: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
		_chk("b25 ...and arg 0 puts it on the other side (%.1f vs %.1f)"
				% [n2.centre.x - atk.x, at.x - atk0.x],
				signf(n2.centre.x - atk.x) != signf(at.x - atk0.x))
		_chk("b25 ...mirrored, not just moved", n2.scale.x < 0.0)
	_step(vm, 6)
	_chk("b25 ...and is gone after 8 frames",
			not is_instance_valid(node) or node.is_finished())


func _test_b25_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	_chk("b25 coverage reaches the sound family's measured level (%d)"
			% int(cov["playable"]), int(cov["playable"]) >= 715)
	for pair in [[47, "Sing"], [187, "Belly Drum"], [253, "Uproar"],
			[336, "Howl"], [405, "Bug Buzz"], [496, "Round"],
			[555, "Snarl"]]:
		_chk("b25 %s plays" % pair[1], _dispatcher.can_play_move(int(pair[0])))


# ── [M36D batch 26] ───────────────────────────────────────────────────────

func _test_b26_moon_uses_absolute_screen_coordinates() -> void:
	# Every other sprite in this port positions relative to a mon, so the
	# tempting read is "offset from the attacker". Moonlight passes (120,56)
	# -- the middle of a 240-wide screen -- which lands on top of the
	# attacker under that reading instead of in the sky.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimMoon", [120, 56], "gMoonSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b26 moon spawned", false)
		return
	var scale: float = stage.pixel_scale()
	var expected := Vector2(120.0, 56.0) * scale
	_chk("b26 the moon sits at the absolute screen point (%.0f,%.0f)"
			% [node.centre.x, node.centre.y],
			node.centre.distance_to(expected) < 1.0)
	var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
	_chk("b26 ...which is NOT an offset from the attacker",
			node.centre.distance_to(atk) > 20.0)


func _test_b26_moon_waits_to_be_killed_rather_than_timing_out() -> void:
	# The moon has no lifetime of its own: AnimTask_MoonlightEndFade sets
	# data[0] on it. A port that gave it a timer would look identical for a
	# few seconds and then desynchronise from the fade it is meant to hide
	# behind.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimMoon", [120, 56], "gMoonSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b26 moon spawned (lifetime)", false)
		return
	_step(r["vm"], 200)
	_chk("b26 the moon is still up after 200 frames with no killer",
			is_instance_valid(node) and not node.is_finished())


func _test_b26_end_fade_kills_the_moon_only_after_the_whiteout() -> void:
	# Ordering is the claim. The kill is state 1, AFTER the 15-step ramp --
	# so the moon vanishes while the screen is already washed out. Killing
	# in state 0 makes it pop out in plain view, and every "the moon dies"
	# assertion still passes.
	var stage := FakeStage.new()
	var moon := _spawn(stage, "AnimMoon", [120, 56], "gMoonSpriteTemplate")
	var node: AnimSprite = moon["sprite"]
	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_MoonlightEndFade").call(vm, {})
	# Both the moon's own stepper and the fade task have to run.
	var moon_vm: AnimScriptVM = moon["vm"]
	for i in range(10):
		_step(vm, 1)
		_step(moon_vm, 1)
	_chk("b26 the moon is STILL up part-way through the whiteout",
			is_instance_valid(node) and not node.is_finished())
	var atk: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	_chk("b26 ...and the battlers are already being washed out",
			atk.material != null)
	for i in range(10):
		_step(vm, 1)
		_step(moon_vm, 1)
	_chk("b26 ...and the moon is gone once the whiteout completes",
			not is_instance_valid(node) or node.is_finished())
	# ...and the fade unwinds rather than leaving the battle white forever.
	_step(vm, 80)
	_chk("b26 ...and the whiteout is cleared afterwards",
			atk.material == null)


func _test_b26_sparkle_creeps_down_and_is_capped() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimMoonlightSparkle", [-12, 0],
			"gMoonlightSparkleSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b26 sparkle spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var scale: float = stage.pixel_scale()
	# Mixed frame of reference: x is relative to the attacker, y is absolute.
	var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
	_chk("b26 the sparkle's x is relative to the attacker",
			absf(node.centre.x - atk.x) < 20.0 * scale)
	_chk("b26 ...while its y is absolute (near the top, not near the mon)",
			node.centre.y < atk.y)
	var y0: float = node.centre.y
	_step(vm, 20)
	var fell: float = (node.centre.y - y0) / scale
	# One pixel every OTHER frame: 20 frames must give about 10, not 20.
	_chk("b26 it creeps down at half a pixel per frame (%.1f over 20)" % fell,
			absf(fell - 10.0) < 1.5)
	# The 120 px cap is the two-sided half -- an uncapped drift walks it off
	# the bottom of the screen instead of parking it.
	_step(vm, 400)
	var total: float = (node.centre.y - y0) / scale
	_chk("b26 ...and stops after 120 px rather than falling forever (%.0f)"
			% total, absf(total - 120.0) < 2.0)


func _test_b26_alpha_fade_in_alternates_its_two_coefficients() -> void:
	# THE FINDING. `data[2]` is a parity counter: odd ticks move eva, even
	# ticks move evb. A 0..16 ramp therefore takes 32 ticks, not 16, and the
	# two coefficients are never more than one step apart. Moving them
	# together halves the duration and changes the curve mid-blend.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	for i in range(5):
		vm.args[i] = [0, 16, 16, 0, 0][i]
	_registry.get_behavior("AnimTask_AlphaFadeIn").call(vm, {})
	_chk("b26 the blend starts where it was told",
			int(vm.blend_context()["eva"]) == 0
			and int(vm.blend_context()["evb"]) == 16)
	# After one tick exactly ONE of the two has moved.
	_step(vm, 1)
	var moved_a: bool = int(vm.blend_context()["eva"]) != 0
	var moved_b: bool = int(vm.blend_context()["evb"]) != 16
	_chk("b26 one tick moves exactly one coefficient, not both",
			moved_a != moved_b)
	# 16 ticks is HALF the ramp under the real reading and the WHOLE ramp
	# under the wrong one, which is what makes this the discriminating
	# sample point.
	_step(vm, 15)
	_chk("b26 ...so it is only half done after 16 ticks (%d, %d)"
			% [int(vm.blend_context()["eva"]), int(vm.blend_context()["evb"])],
			int(vm.blend_context()["eva"]) != 16
			or int(vm.blend_context()["evb"]) != 0)
	_step(vm, 20)
	_chk("b26 ...and lands exactly on target after 32 (%d, %d)"
			% [int(vm.blend_context()["eva"]), int(vm.blend_context()["evb"])],
			int(vm.blend_context()["eva"]) == 16
			and int(vm.blend_context()["evb"]) == 0)


func _test_b26_attacker_fade_from_invisible_is_the_inverse() -> void:
	# Batch 20 built the fade OUT. This is its partner, and the pair has to
	# leave the attacker solid and unblended -- a script that faded it out
	# and back must not end with a half-transparent mon.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0
	var atk: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	_registry.get_behavior("AnimTask_InitAttackerFadeFromInvisible").call(vm, {})
	_chk("b26 arming makes the attacker visible but fully blended",
			atk.visible and atk.material != null)
	_registry.get_behavior("AnimTask_AttackerFadeFromInvisible").call(vm, {})
	_step(vm, 8)
	_chk("b26 the attacker is part-way back mid-fade", atk.material != null)
	_step(vm, 12)
	_chk("b26 ...and ends solid, with the blend cleared",
			atk.material == null and atk.visible)


func _test_b26_sky_bird_flies_from_attacker_through_target() -> void:
	# Two claims a single "it moves" check cannot separate. The bird is
	# CREATED at the target and then teleported to the attacker, so getting
	# the direction backwards is a live possibility; and it never stops --
	# arriving is not the end of its flight.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimSkyAttackBird", [],
			"gSkyAttackBirdSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b26 sky bird spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
	var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	_chk("b26 the bird starts on the ATTACKER, not where it was created",
			node.centre.distance_to(atk) < node.centre.distance_to(tgt))
	_step(vm, 12)
	_chk("b26 ...reaches the target on frame 12 (%.0f away)"
			% node.centre.distance_to(tgt),
			node.centre.distance_to(tgt) < atk.distance_to(tgt) * 0.15)
	# The swoop-through: at frame 24 it must be roughly as far PAST the
	# target as it started before it. Stopping on arrival reads as landing.
	_step(vm, 12)
	_chk("b26 ...and keeps going past it rather than landing (%.0f past)"
			% node.centre.distance_to(tgt),
			node.centre.distance_to(tgt) > atk.distance_to(tgt) * 0.5)
	_chk("b26 ...and is rotated to face its flight", absf(node.rotation) > 0.01)


func _test_b26_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	_chk("b26 coverage reaches the fade family's measured level (%d)"
			% int(cov["playable"]), int(cov["playable"]) >= 725)
	for pair in [[143, "Sky Attack"], [185, "Feint Attack"], [236, "Moonlight"],
			[361, "Healing Wish"], [413, "Brave Bird"], [461, "Lunar Dance"]]:
		_chk("b26 %s plays" % pair[1], _dispatcher.can_play_move(int(pair[0])))
	# The spotlight trio is DEFERRED, not missed. If a later session ports
	# the stencil surface these light up together; until then the three moves
	# must still be correctly reported as unplayable rather than silently
	# half-working.
	for pair in [[634, "Spotlight"], [652, "Instruct"], [798, "Flower Trick"]]:
		_chk("b26 %s stays deferred (WIN0/WIN1 stencil)" % pair[1],
				not _dispatcher.can_play_move(int(pair[0])))


# ── [M36D batch 27] ───────────────────────────────────────────────────────

func _test_b27_duplicate_pairs_are_aliases() -> void:
	# Upstream duplicated two functions rather than calling them. Asserting
	# identity keeps a later session from "porting" either separately and
	# ending up with two implementations to keep in step -- the same guard
	# batch 24 put on the gunk-shot particles.
	_chk("b27 AnimGrassKnot IS AnimSuckerPunch, not a copy",
			_registry.get_behavior("AnimGrassKnot")
			== _registry.get_behavior("AnimSuckerPunch"))
	_chk("b27 AnimForcePalm IS AnimGunkShotImpact, not a copy",
			_registry.get_behavior("AnimForcePalm")
			== _registry.get_behavior("AnimGunkShotImpact"))


func _test_b27_conversion_dies_only_on_the_arg7_signal() -> void:
	# The first behavior in the port that could not have worked before batch
	# 24: the square polls arg 7 and dies on 0xFFFF, and the old `_load_args`
	# cleared arg 7 on every command. Without a signal it must live forever.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimConversion", [-24, -24],
			"gConversionSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b27 conversion square spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	_step(vm, 200)
	_chk("b27 the square outlives 200 frames with no signal",
			is_instance_valid(node) and not node.is_finished())
	vm.args[AnimScriptVM.ARG_RET] = 0xFFFF
	_step(vm, 1)
	_chk("b27 ...and dies the frame the signal arrives",
			not is_instance_valid(node) or node.is_finished())
	# Two-sided: any other value must NOT kill it, or the square would
	# vanish on the first unrelated query task that writes arg 7.
	var s2 := FakeStage.new()
	var r2 := _spawn(s2, "AnimConversion", [8, -8], "gConversionSpriteTemplate")
	var n2: AnimSprite = r2["sprite"]
	if n2 != null:
		r2["vm"].args[AnimScriptVM.ARG_RET] = 1
		_step(r2["vm"], 5)
		_chk("b27 ...and ignores any other arg-7 value",
				is_instance_valid(n2) and not n2.is_finished())


func _test_b27_conversion_blend_signals_only_after_its_ramp() -> void:
	# Ordering again: the kill is written AFTER the 16-step ramp completes,
	# so the squares fade with the blend instead of popping mid-fade.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_ConversionAlphaBlend").call(vm, {})
	_step(vm, 30)
	_chk("b27 no signal part-way through the ramp (arg7 = %d)"
			% vm.args[AnimScriptVM.ARG_RET],
			(vm.args[AnimScriptVM.ARG_RET] & 0xFFFF) != 0xFFFF)
	_chk("b27 ...but the blend is already moving (%d, %d)"
			% [int(vm.blend_context()["eva"]), int(vm.blend_context()["evb"])],
			int(vm.blend_context()["evb"]) > 0)
	_step(vm, 45)
	_chk("b27 ...and the signal lands once the ramp completes",
			(vm.args[AnimScriptVM.ARG_RET] & 0xFFFF) == 0xFFFF)
	_chk("b27 ...with the blend fully over (%d, %d)"
			% [int(vm.blend_context()["eva"]), int(vm.blend_context()["evb"])],
			int(vm.blend_context()["evb"]) == 16
			and int(vm.blend_context()["eva"]) == 0)


func _test_b27_tri_attack_flickers_holds_then_launches() -> void:
	# Three beats. A port that flickered the whole time, or launched at once,
	# still looks busy -- so each boundary is asserted, not just the launch.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimTriAttackTriangle", [0, 0],
			"gTriAttackTriangleSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b27 tri-attack triangle spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var start: Vector2 = node.centre
	var seen_hidden := false
	for i in range(30):
		_step(vm, 1)
		if not node.visible:
			seen_hidden = true
	_chk("b27 it flickers for the first 30 frames", seen_hidden)
	var solid := true
	for i in range(28):
		_step(vm, 1)
		if not node.visible:
			solid = false
	_chk("b27 ...then holds SOLID from 31 to 60", solid)
	_chk("b27 ...without having moved yet",
			node.centre.distance_to(start) < 1.0)
	_step(vm, 12)
	_chk("b27 ...and only then launches at the target",
			node.centre.distance_to(start) > 1.0)


func _test_b27_sharpen_sphere_blink_period_grows() -> void:
	# The period GROWS (data[1] starts at 2 and increments every second
	# toggle). A fixed-rate blink is the obvious misreading and never
	# settles, so the test measures the gap between toggles rather than
	# merely that it blinks.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimSharpenSphere", [],
			"gSharpenSphereSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b27 sharpen sphere spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var gaps: Array = []
	var last := 0
	var was: bool = node.visible
	for i in range(1, 260):
		_step(vm, 1)
		if not is_instance_valid(node) or node.is_finished():
			break
		if node.visible != was:
			was = node.visible
			gaps.append(i - last)
			last = i
	_chk("b27 the sphere blinks a good many times (%d)" % gaps.size(),
			gaps.size() >= 8)
	if gaps.size() >= 8:
		var early: int = int(gaps[1]) + int(gaps[2])
		var late: int = int(gaps[gaps.size() - 2]) + int(gaps[gaps.size() - 1])
		_chk("b27 ...and slows down rather than strobing evenly (%d -> %d)"
				% [early, late], late > early)
	_step(vm, 40)
	_chk("b27 ...and stops once its period passes 16",
			not is_instance_valid(node) or node.is_finished())


func _test_b27_stealth_rock_arcs_holds_then_blinks_out() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimStealthRock", [0, 0, 0, 0, 30],
			"gStealthRockSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b27 stealth rock spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var start: Vector2 = node.centre
	var aim: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	_step(vm, 15)
	var chord: Vector2 = start.lerp(aim, 0.5)
	_chk("b27 the rock arcs ABOVE the straight line (%.1f)"
			% (chord.y - node.centre.y), node.centre.y < chord.y - 5.0)
	_step(vm, 15)
	var landed: Vector2 = node.centre
	_step(vm, 25)
	_chk("b27 ...then HOLDS where it landed rather than continuing",
			node.centre.distance_to(landed) < 1.0)
	_chk("b27 ...and is still visible during the hold", node.visible)
	var blinked := false
	for i in range(20):
		_step(vm, 1)
		if is_instance_valid(node) and not node.visible:
			blinked = true
	_chk("b27 ...then blinks out", blinked)
	_step(vm, 5)
	_chk("b27 ...and is gone", not is_instance_valid(node) or node.is_finished())


func _test_b27_breath_puff_drifts_away_from_its_own_side() -> void:
	var player := FakeStage.new()
	var rp := _spawn(player, "AnimBreathPuff", [], "gBreathPuffSpriteTemplate")
	var foe := FakeStage.new()
	foe.player_side = false
	var rf := _spawn(foe, "AnimBreathPuff", [], "gBreathPuffSpriteTemplate")
	var np: AnimSprite = rp["sprite"]
	var nf: AnimSprite = rf["sprite"]
	if np == null or nf == null:
		_chk("b27 breath puffs spawned", false)
		return
	var sp: Vector2 = np.centre
	var sf: Vector2 = nf.centre
	_step(rp["vm"], 40)
	_step(rf["vm"], 40)
	_chk("b27 the puff drifts sideways (%.1f)" % (np.centre.x - sp.x),
			absf(np.centre.x - sp.x) > 1.0)
	_chk("b27 ...and the two sides drift OPPOSITE ways (%.1f vs %.1f)"
			% [np.centre.x - sp.x, nf.centre.x - sf.x],
			signf(np.centre.x - sp.x) != signf(nf.centre.x - sf.x))
	_step(rp["vm"], 15)
	_chk("b27 ...and it is gone after 52 frames",
			not is_instance_valid(np) or np.is_finished())


func _test_b27_grow_and_shrink_returns_to_identity() -> void:
	var sum_x := 0
	var sum_y := 0
	for cmd in AnimBehaviors._GROW_SHRINK_AFFINE:
		sum_x += int(cmd[0]) * int(cmd[3])
		sum_y += int(cmd[1]) * int(cmd[3])
	_chk("b27 _GROW_SHRINK_AFFINE sums to identity (%d/%d)" % [sum_x, sum_y],
			sum_x == 0 and sum_y == 0)
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var node: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	var base: Vector2 = node.scale
	_registry.get_behavior("AnimTask_GrowAndShrink").call(vm, {})
	_step(vm, 12)
	# Negative deltas under the INVERTED rule mean the mon gets BIGGER --
	# the name is the check, and getting the inversion backwards shrinks it.
	_chk("b27 the mon actually GROWS (%.3f)" % (node.scale.x / base.x),
			node.scale.x > base.x)
	_step(vm, 40)
	_chk("b27 ...and is back to its true size",
			node.scale.is_equal_approx(base))


func _test_b27_sucker_punch_slides_and_its_wave_is_inert() -> void:
	# ⚠ A CLAIM I INVENTED AND THE TEST CAUGHT. The first draft asserted the
	# sprite "waves vertically", reasoning from the Sin() call in the step
	# function. Both real call sites pass amplitude ZERO --
	# `-18, 5, 40, 8, 160, 0` for Sucker Punch and `-18, 19, 40, 8, 160, 0`
	# for Grass Knot -- so the sine term is inert in every animation that
	# actually reaches it, and the sprite slides flat. Reading a Sin() call
	# as "therefore it waves" is the mistake; the args decide.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimSuckerPunch", [-18, 5, 40, 8, 160, 0],
			"gSuckerPunchSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b27 sucker punch spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var start_pos: Vector2 = node.centre
	var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	_chk("b27 it starts offset from the TARGET, not the attacker",
			node.centre.distance_to(tgt)
			< node.centre.distance_to(stage.center_of(AnimStage.ANIM_ATTACKER)))
	var max_dy := 0.0
	for i in range(7):
		_step(vm, 1)
		if is_instance_valid(node):
			max_dy = maxf(max_dy, absf(node.centre.y - start_pos.y))
	_chk("b27 it slides horizontally (%.1f)"
			% (node.centre.x - start_pos.x),
			absf(node.centre.x - start_pos.x) > 1.0)
	_chk("b27 ...and stays FLAT with the real args (max dy %.2f)" % max_dy,
			max_dy < 1.0)

	# The sine is still wired, and this is the half that proves the code is
	# not dead: given a real amplitude it does move vertically. Without this
	# the check above would also pass for a port that dropped the term.
	var s2 := FakeStage.new()
	var r2 := _spawn(s2, "AnimSuckerPunch", [-18, 5, 40, 30, 900, 12],
			"gSuckerPunchSpriteTemplate")
	var n2: AnimSprite = r2["sprite"]
	if n2 != null:
		var sy: float = n2.centre.y
		var moved := 0.0
		for i in range(29):
			_step(r2["vm"], 1)
			if is_instance_valid(n2):
				moved = maxf(moved, absf(n2.centre.y - sy))
		_chk("b27 ...but a real amplitude DOES move it (%.1f)" % moved,
				moved > 1.0)


func _test_b27_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	_chk("b27 coverage reaches the measured level (%d)" % int(cov["playable"]),
			int(cov["playable"]) >= 740)
	for pair in [[159, "Sharpen"], [160, "Conversion"], [161, "Tri Attack"],
			[162, "Super Fang"], [389, "Sucker Punch"], [395, "Force Palm"],
			[446, "Stealth Rock"], [447, "Grass Knot"], [469, "Wide Guard"]]:
		_chk("b27 %s plays" % pair[1], _dispatcher.can_play_move(int(pair[0])))
	# Rapid Spin's family was deferred here WITH its scanline partner rather
	# than half-ported; batch 37 built that surface, so they now PLAY. The
	# prediction ("these light up together") held exactly.
	for pair in [[229, "Rapid Spin"], [789, "Ice Spinner"]]:
		_chk("b27 %s plays (scanline surface built in b37)" % pair[1],
				_dispatcher.can_play_move(int(pair[0])))


# ── [M36D batch 28] ───────────────────────────────────────────────────────

func _test_b28_affine_table_sums_and_the_one_exception() -> void:
	# Transcription guards. Most tables return to identity; ONE does not, and
	# knowing which is the point -- gShrinkAndGrowAffineAnimCmds goes out over
	# 12 frames and back over 6, so it nets +24/+30. It is safe only because
	# AFFINEANIMCMDTYPE_END resets the sprite regardless, which is exactly why
	# these assertions guard transcription rather than leaks.
	for pair in [["_MEDITATE_STRETCH_AFFINE",
				AnimBehaviors._MEDITATE_STRETCH_AFFINE],
			["_SLACK_OFF_AFFINE", AnimBehaviors._SLACK_OFF_AFFINE],
			["_COMPRESS_AFFINE", AnimBehaviors._COMPRESS_AFFINE],
			["_COMPRESS_FAST_AFFINE", AnimBehaviors._COMPRESS_FAST_AFFINE],
			["_FACADE_SQUISH_AFFINE", AnimBehaviors._FACADE_SQUISH_AFFINE]]:
		var sx := 0
		var sy := 0
		for cmd in (pair[1] as Array):
			sx += int(cmd[0]) * int(cmd[3])
			sy += int(cmd[1]) * int(cmd[3])
		_chk("b28 %s sums to identity (%d/%d)" % [pair[0], sx, sy],
				sx == 0 and sy == 0)
	var ax := 0
	var ay := 0
	for cmd in AnimBehaviors._SHRINK_GROW_AFFINE:
		ax += int(cmd[0]) * int(cmd[3])
		ay += int(cmd[1]) * int(cmd[3])
	_chk("b28 _SHRINK_GROW_AFFINE is the asymmetric one (%d/%d)" % [ax, ay],
			ax == 24 and ay == 30)
	# ...and the runtime still puts the mon back, which is what makes the
	# asymmetry harmless.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var node: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	var base: Vector2 = node.scale
	_registry.get_behavior("AnimTask_ShrinkAndGrow").call(vm, {})
	_step(vm, 60)
	_chk("b28 ...and the asymmetric table still ends at true size",
			node.scale.is_equal_approx(base))


func _test_b28_grow_tasks_use_the_inverted_scale() -> void:
	# 208 in GBA affine units is a GROWTH to 256/208 = 1.23x. Read as a
	# direct multiplier it shrinks the mon to a fifth -- the opposite
	# silhouette, and still a smooth effect.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var node: Control = stage.sprite_for(AnimStage.ANIM_TARGET)
	var base: Vector2 = node.scale
	_registry.get_behavior("AnimTask_GrowTarget").call(vm, {})
	_step(vm, 5)
	_chk("b28 the target GROWS (%.3f)" % (node.scale.x / base.x),
			node.scale.x > base.x * 1.1)
	_step(vm, 130)
	_chk("b28 ...and is restored after 120 frames",
			node.scale.is_equal_approx(base))
	# The grayscale variant additionally drains the colour, and puts it back.
	var s2 := FakeStage.new()
	var vm2 := _vm(s2)
	var n2: Control = s2.sprite_for(AnimStage.ANIM_TARGET)
	var mod0: Color = n2.modulate
	_registry.get_behavior("AnimTask_GrowAndGrayscale").call(vm2, {})
	_step(vm2, 5)
	_chk("b28 the grayscale variant drains colour",
			not n2.modulate.is_equal_approx(mod0))
	_chk("b28 ...and grows as well as greying", n2.scale.x > base.x * 1.1)
	_step(vm2, 90)
	_chk("b28 ...and restores both", n2.modulate.is_equal_approx(mod0)
			and n2.scale.is_equal_approx(base))
	# Two-sided on duration: 80 frames, not 120 -- the two tasks differ.
	var s3 := FakeStage.new()
	var vm3 := _vm(s3)
	var n3: Control = s3.sprite_for(AnimStage.ANIM_TARGET)
	_registry.get_behavior("AnimTask_GrowAndGrayscale").call(vm3, {})
	_step(vm3, 85)
	var grey_done: bool = n3.scale.is_equal_approx(base)
	var s4 := FakeStage.new()
	var vm4 := _vm(s4)
	var n4: Control = s4.sprite_for(AnimStage.ANIM_TARGET)
	_registry.get_behavior("AnimTask_GrowTarget").call(vm4, {})
	_step(vm4, 85)
	_chk("b28 grayscale ends at 80 while grow-target is still running at 85",
			grey_done and not n4.scale.is_equal_approx(base))


func _test_b28_withdraw_rotates_rather_than_moving() -> void:
	# The tuck is a ROTATION. A port that translated the mon instead would
	# read as it sliding away, and every "something changed" check passes.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var node: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	var pos0: Vector2 = node.position
	_registry.get_behavior("AnimTask_Withdraw").call(vm, {})
	_step(vm, 8)
	_chk("b28 the attacker rotates (%.3f rad)" % node.rotation,
			absf(node.rotation) > 0.01)
	_chk("b28 ...and does NOT translate", node.position.is_equal_approx(pos0))
	# Mirrored by side, so both tuck the same way relative to the screen.
	var foe := FakeStage.new()
	foe.player_side = false
	var vm2 := _vm(foe)
	var n2: Control = foe.sprite_for(AnimStage.ANIM_ATTACKER)
	_registry.get_behavior("AnimTask_Withdraw").call(vm2, {})
	_step(vm2, 8)
	_chk("b28 ...the other side rotates the OTHER way (%.3f vs %.3f)"
			% [node.rotation, n2.rotation],
			signf(node.rotation) != signf(n2.rotation))
	_step(vm, 60)
	_chk("b28 ...and it unwinds to square", absf(node.rotation) < 0.001)


func _test_b28_rotate_vertically_limits_differ_by_side() -> void:
	# NOT a mirror: the player side stops at 0x1FFF (~45 degrees) while the
	# opponent goes to 0x7FFE (~180, fully over). One shared limit gives a
	# player mon that flips when it should only tilt.
	var player := FakeStage.new()
	var vp := _vm(player)
	vp.args[0] = AnimStage.ANIM_ATTACKER
	vp.args[1] = 512
	var np: Control = player.sprite_for(AnimStage.ANIM_ATTACKER)
	_registry.get_behavior("AnimTask_RotateVertically").call(vp, {})
	_step(vp, 40)
	var foe := FakeStage.new()
	foe.player_side = false
	var vf := _vm(foe)
	vf.args[0] = AnimStage.ANIM_ATTACKER
	vf.args[1] = 512
	var nf: Control = foe.sprite_for(AnimStage.ANIM_ATTACKER)
	_registry.get_behavior("AnimTask_RotateVertically").call(vf, {})
	_step(vf, 40)
	_chk("b28 both sides rotate (%.2f / %.2f)" % [np.rotation, nf.rotation],
			absf(np.rotation) > 0.01 and absf(nf.rotation) > 0.01)
	_chk("b28 ...but the opponent goes MUCH further (%.2f vs %.2f)"
			% [nf.rotation, np.rotation],
			absf(nf.rotation) > absf(np.rotation) * 2.0)
	_step(vp, 200)
	_chk("b28 ...and the player mon unwinds to square",
			absf(np.rotation) < 0.001)


func _test_b28_minimize_shrinks_but_double_team_does_not() -> void:
	# Both leave afterimages, and that is the whole reason to test them
	# together: only Minimize deforms the mon. A port that shrank on Double
	# Team too would look busy and wrong in the same way.
	var s1 := FakeStage.new()
	var v1 := _vm(s1)
	var n1: Control = s1.sprite_for(AnimStage.ANIM_ATTACKER)
	var base: Vector2 = n1.scale
	_registry.get_behavior("AnimTask_Minimize").call(v1, {})
	_step(v1, 16)
	_chk("b28 Minimize SHRINKS the attacker (%.3f)" % (n1.scale.x / base.x),
			n1.scale.x < base.x * 0.9)
	_chk("b28 ...and leaves clones behind", _clone_count(s1) > 0)
	_step(v1, 20)
	_chk("b28 ...then restores its size and clears the clones",
			n1.scale.is_equal_approx(base) or _clone_count(s1) == 0)

	var s2 := FakeStage.new()
	var v2 := _vm(s2)
	var n2: Control = s2.sprite_for(AnimStage.ANIM_ATTACKER)
	var b2: Vector2 = n2.scale
	_registry.get_behavior("AnimTask_DoubleTeam").call(v2, {})
	_step(v2, 16)
	_chk("b28 Double Team makes clones", _clone_count(s2) >= 2)
	_chk("b28 ...and does NOT shrink the mon", n2.scale.is_equal_approx(b2))
	# The clones must actually sweep, and the two must not overlap -- upstream
	# seeds them half a cycle apart precisely so they separate.
	var xs: Array = []
	for child in s2.layer_node.get_children():
		if child is Control and child.has_meta("_anim_trace"):
			xs.append((child as Control).position.x)
	if xs.size() >= 2:
		_chk("b28 ...and its two clones are apart, not stacked (%.1f)"
				% absf(float(xs[0]) - float(xs[1])),
				absf(float(xs[0]) - float(xs[1])) > 0.5)


func _test_b28_squish_count_is_a_gate_and_a_multiplier() -> void:
	# A count of 0 must do nothing at all -- upstream destroys the task before
	# touching the sprite, so the arg is a gate rather than a minimum.
	var s0 := FakeStage.new()
	var v0 := _vm(s0)
	v0.args[0] = AnimStage.ANIM_ATTACKER
	v0.args[1] = 0
	var before := v0._visual_count
	_registry.get_behavior("AnimTask_SquishAndSweatDroplets").call(v0, {})
	_chk("b28 a squish count of 0 starts nothing", v0._visual_count == before)
	# ...and a count of N runs N passes, so 3 lasts about three times as long
	# as 1. Duration is the only thing that separates them.
	var one := FakeStage.new()
	var v1 := _vm(one)
	v1.args[0] = AnimStage.ANIM_ATTACKER
	v1.args[1] = 1
	var n1: Control = one.sprite_for(AnimStage.ANIM_ATTACKER)
	var b1: Vector2 = n1.scale
	_registry.get_behavior("AnimTask_SquishAndSweatDroplets").call(v1, {})
	_step(v1, 25)
	var one_done: bool = n1.scale.is_equal_approx(b1)
	var three := FakeStage.new()
	var v3 := _vm(three)
	v3.args[0] = AnimStage.ANIM_ATTACKER
	v3.args[1] = 3
	var n3: Control = three.sprite_for(AnimStage.ANIM_ATTACKER)
	_registry.get_behavior("AnimTask_SquishAndSweatDroplets").call(v3, {})
	_step(v3, 25)
	_chk("b28 one squish is over by frame 25 while three is not",
			one_done and not n3.scale.is_equal_approx(b1))
	_step(v3, 60)
	_chk("b28 ...and three squishes still end at true size",
			n3.scale.is_equal_approx(b1))


func _test_b28_compress_pair_differs_only_in_depth() -> void:
	var slow := FakeStage.new()
	var vs := _vm(slow)
	var ns: Control = slow.sprite_for(AnimStage.ANIM_TARGET)
	var base: Vector2 = ns.scale
	_registry.get_behavior("AnimTask_CompressTargetHorizontally").call(vs, {})
	_step(vs, 16)
	var fast := FakeStage.new()
	var vf := _vm(fast)
	var nf: Control = fast.sprite_for(AnimStage.ANIM_TARGET)
	_registry.get_behavior("AnimTask_CompressTargetHorizontallyFast").call(vf, {})
	_step(vf, 16)
	_chk("b28 both compress horizontally (%.3f / %.3f)"
			% [ns.scale.x / base.x, nf.scale.x / base.x],
			ns.scale.x < base.x and nf.scale.x < base.x)
	_chk("b28 ...and the plain one compresses FURTHER than the fast one",
			ns.scale.x < nf.scale.x)
	# Neither touches the vertical -- the tables are x-only.
	_chk("b28 ...with the vertical untouched",
			is_equal_approx(ns.scale.y, base.y)
			and is_equal_approx(nf.scale.y, base.y))


func _test_b28_duck_down_hop_mirrors_by_side() -> void:
	var player := FakeStage.new()
	var vp := _vm(player)
	for i in range(7):
		vp.args[i] = [AnimStage.ANIM_ATTACKER, 20, 0, 8, 0, -12, 6][i]
	var np: Control = player.sprite_for(AnimStage.ANIM_ATTACKER)
	var p0: Vector2 = np.position
	_registry.get_behavior("AnimTask_DuckDownHop").call(vp, {})
	_step(vp, 10)
	var foe := FakeStage.new()
	foe.player_side = false
	var vf := _vm(foe)
	for i in range(7):
		vf.args[i] = [AnimStage.ANIM_ATTACKER, 20, 0, 8, 0, -12, 6][i]
	var nf: Control = foe.sprite_for(AnimStage.ANIM_ATTACKER)
	var f0: Vector2 = nf.position
	_registry.get_behavior("AnimTask_DuckDownHop").call(vf, {})
	_step(vf, 10)
	_chk("b28 the hop moves the mon (%.1f, %.1f)"
			% [np.position.x - p0.x, np.position.y - p0.y],
			not np.position.is_equal_approx(p0))
	_chk("b28 ...and the two sides duck OPPOSITE ways (%.1f vs %.1f)"
			% [np.position.x - p0.x, nf.position.x - f0.x],
			signf(np.position.x - p0.x) != signf(nf.position.x - f0.x))
	_step(vp, 12)
	_chk("b28 ...and it returns the mon", np.position.is_equal_approx(p0))


func _test_b28_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	_chk("b28 coverage reaches the measured level (%d)" % int(cov["playable"]),
			int(cov["playable"]) >= 753)
	for pair in [[50, "Disable"], [96, "Meditate"], [104, "Double Team"],
			[107, "Minimize"], [110, "Withdraw"], [303, "Slack Off"],
			[462, "Crush Grip"], [576, "Topsy-Turvy"]]:
		_chk("b28 %s plays" % pair[1], _dispatcher.can_play_move(int(pair[0])))
	# The two deferrals, asserted as still-blocked so a half-port cannot pass.
	for pair in [[151, "Acid Armor"], [144, "Transform"]]:
		_chk("b28 %s stays deferred (scanline / mosaic)" % pair[1],
				not _dispatcher.can_play_move(int(pair[0])))


# ── [M36D batch 29] ───────────────────────────────────────────────────────

func _test_b29_spit_up_spray_is_elliptical_not_circular() -> void:
	# The two axes use DIFFERENT amplitudes (10 and 7), so the spray is wider
	# than it is tall. A single shared amplitude gives a circular burst --
	# still a burst, wrong shape, and every "it moves outward" check passes.
	var widest := 0.0
	var tallest := 0.0
	for angle in [0, 32, 64, 96, 128, 160, 192, 224]:
		var stage := FakeStage.new()
		var r := _spawn(stage, "AnimSpitUpOrb", [angle, 20],
				"gSpitUpOrbSpriteTemplate")
		var node: AnimSprite = r["sprite"]
		if node == null:
			continue
		var start: Vector2 = node.centre
		_step(r["vm"], 15)
		widest = maxf(widest, absf(node.centre.x - start.x))
		tallest = maxf(tallest, absf(node.centre.y - start.y))
	_chk("b29 the spit-up spray travels outward (%.1f x %.1f)"
			% [widest, tallest], widest > 1.0 and tallest > 1.0)
	_chk("b29 ...and is WIDER than it is tall (10 vs 7)", widest > tallest)


func _test_b29_swallow_orb_decelerates_and_falls_back() -> void:
	# A DECELERATING rise, ended by falling back below its launch height --
	# not a timer. A constant-velocity rise never comes back and never ends.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimSwallowBlueOrb", [],
			"gSwallowBlueOrbSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b29 swallow orb spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var start: Vector2 = node.centre
	var first := 0.0
	var last := 0.0
	var prev: float = node.centre.y
	_step(vm, 1)
	first = prev - node.centre.y
	prev = node.centre.y
	for i in range(8):
		_step(vm, 1)
		last = prev - node.centre.y
		prev = node.centre.y
	_chk("b29 the orb rises (%.1f)" % (start.y - node.centre.y),
			node.centre.y < start.y)
	_chk("b29 ...and DECELERATES as it goes (%.2f -> %.2f)" % [first, last],
			last < first)
	# It must actually come back and end, rather than drifting off the top.
	var ended := false
	for i in range(80):
		_step(vm, 1)
		if not is_instance_valid(node) or node.is_finished():
			ended = true
			break
	_chk("b29 ...then falls back and ends on its own", ended)


func _test_b29_bonemerang_comes_back() -> void:
	# The return leg is the whole move. A one-way arc still lands on the
	# target and still looks like a thrown bone.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimBonemerangProjectile", [],
			"gBonemerangSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b29 bonemerang spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
	var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	_step(vm, 10)
	var mid: Vector2 = node.centre
	var chord: Vector2 = atk.lerp(tgt, 0.5)
	_chk("b29 it arcs above the chord outbound (%.1f)" % (chord.y - mid.y),
			mid.y < chord.y - 5.0)
	_step(vm, 11)
	_chk("b29 ...reaches the target", node.centre.distance_to(tgt)
			< atk.distance_to(tgt) * 0.35)
	_step(vm, 18)
	_chk("b29 ...and comes BACK toward the attacker (%.0f from atk)"
			% node.centre.distance_to(atk),
			node.centre.distance_to(atk) < node.centre.distance_to(tgt))


func _test_b29_wish_star_enters_from_the_far_side() -> void:
	# It enters off-screen on the side OPPOSITE the caster, so the wish
	# crosses toward the caster's own half. Both sides checked, because one
	# alone cannot tell an entry direction from a fixed one.
	var player := FakeStage.new()
	var rp := _spawn(player, "AnimWishStar", [], "gWishStarSpriteTemplate")
	var foe := FakeStage.new()
	foe.player_side = false
	var rf := _spawn(foe, "AnimWishStar", [], "gWishStarSpriteTemplate")
	var np: AnimSprite = rp["sprite"]
	var nf: AnimSprite = rf["sprite"]
	if np == null or nf == null:
		_chk("b29 wish stars spawned", false)
		return
	var w: float = player.layer_node.size.x
	_chk("b29 a player wish enters from the RIGHT edge (%.0f of %.0f)"
			% [np.centre.x, w], np.centre.x > w * 0.9)
	_chk("b29 ...and an opposing one from the LEFT (%.0f)" % nf.centre.x,
			nf.centre.x < w * 0.1)
	var p0: Vector2 = np.centre
	_step(rp["vm"], 4)
	var early: float = absf(np.centre.x - p0.x)
	_step(rp["vm"], 4)
	var late: float = absf(np.centre.x - p0.x) - early
	_chk("b29 ...and it ACCELERATES across (%.1f -> %.1f)" % [early, late],
			late > early)


func _test_b29_angel_path_is_circular_and_slides_off() -> void:
	# Sin and Cos share amplitude 80, so the loop is a circle. Different
	# amplitudes would give an ellipse -- a real distinction, since the
	# neighbouring Spit Up orb IS elliptical on purpose.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimAngel", [0, 0], "gAngelSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b29 angel spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var start: Vector2 = node.centre
	var max_x := 0.0
	var min_y := 0.0
	for i in range(70):
		_step(vm, 1)
		if is_instance_valid(node):
			max_x = maxf(max_x, absf(node.centre.x - start.x))
			min_y = minf(min_y, node.centre.y - start.y)
	_chk("b29 the angel loops sideways (%.1f)" % max_x, max_x > 1.0)
	_chk("b29 ...and drifts DOWN over its first 80 frames (%.1f)"
			% (node.centre.y - start.y), node.centre.y > start.y)
	# The slide-off after frame 90 is a separate leg.
	var before: float = node.centre.x
	_step(vm, 25)
	_chk("b29 ...then slides away sideways (%.1f)"
			% (node.centre.x - before), node.centre.x < before)
	_step(vm, 15)
	_chk("b29 ...and ends", not is_instance_valid(node) or node.is_finished())


func _test_b29_meteor_star_sweeps_inward_on_both_sides() -> void:
	# The X offsets are subtracted for a player-side target and added for an
	# opposing one, so the stars always sweep INWARD. One shared sign sends
	# them off-screen on one side.
	var a := FakeStage.new()
	var ra := _spawn(a, "AnimMeteorMashStar", [40, 0, 0, 0, 10],
			"gMeteorMashStarSpriteTemplate")
	var b := FakeStage.new()
	b.player_side = false
	var rb := _spawn(b, "AnimMeteorMashStar", [40, 0, 0, 0, 10],
			"gMeteorMashStarSpriteTemplate")
	var na: AnimSprite = ra["sprite"]
	var nb: AnimSprite = rb["sprite"]
	if na == null or nb == null:
		_chk("b29 meteor stars spawned", false)
		return
	var ca: Vector2 = a.center_of(AnimStage.ANIM_TARGET)
	var cb: Vector2 = b.center_of(AnimStage.ANIM_TARGET)
	_chk("b29 the two sides start on OPPOSITE sides of the target (%.1f vs %.1f)"
			% [na.centre.x - ca.x, nb.centre.x - cb.x],
			signf(na.centre.x - ca.x) != signf(nb.centre.x - cb.x))
	_step(ra["vm"], 9)
	_chk("b29 ...and both close on it",
			na.centre.distance_to(ca) < absf(40.0 * a.pixel_scale()))


func _test_b29_yawn_cloud_drifts_then_blinks_out() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimYawnCloud", [0], "gYawnCloudSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b29 yawn cloud spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
	var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	_chk("b29 it starts on the attacker",
			node.centre.distance_to(atk) < node.centre.distance_to(tgt))
	_step(vm, 50)
	_chk("b29 ...and drifts toward the target",
			node.centre.distance_to(tgt) < node.centre.distance_to(atk))
	var blinked := false
	for i in range(16):
		_step(vm, 1)
		if is_instance_valid(node) and not node.visible:
			blinked = true
	_chk("b29 ...then blinks out rather than vanishing", blinked)
	_step(vm, 10)
	_chk("b29 ...and is gone",
			not is_instance_valid(node) or node.is_finished())


func _test_b29_fade_in_pair_starts_invisible() -> void:
	# Both open by arming BLDALPHA to (0,16) -- fully transparent -- and
	# fade in. A port that skipped the arming has them pop in at full
	# opacity, which no other assertion here would notice.
	for pair in [["AnimMilkBottle", "gMilkBottleSpriteTemplate"],
			["AnimMeanLookEye", "gMeanLookEyeSpriteTemplate"]]:
		var stage := FakeStage.new()
		var r := _spawn(stage, str(pair[0]), [], str(pair[1]))
		var node: AnimSprite = r["sprite"]
		if node == null:
			_chk("b29 %s spawned" % pair[0], false)
			continue
		_chk("b29 %s starts fully transparent (a=%.2f)"
				% [pair[0], node.modulate.a], node.modulate.a < 0.01)
		_step(r["vm"], 8)
		_chk("b29 %s ...is part-way in after 8 frames (a=%.2f)"
				% [pair[0], node.modulate.a],
				node.modulate.a > 0.1 and node.modulate.a < 0.99)
		_step(r["vm"], 12)
		_chk("b29 %s ...and reaches full opacity" % pair[0],
				node.modulate.a > 0.99)


func _test_b29_string_wrap_uses_the_target_side_midpoint() -> void:
	# It anchors on SetAverageBattlerPositions, which in doubles is the
	# midpoint of both opposing slots -- batch 23's `_side_centre`. A
	# single-slot anchor is indistinguishable in singles, so the doubles
	# case is the one that separates them.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimStringWrap", [0, 0],
			"gStringWrapSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b29 string wrap spawned", false)
		return
	var mid: Vector2 = (stage.center_of(AnimStage.ANIM_TARGET)
			+ stage.center_of(AnimStage.ANIM_DEF_PARTNER)) * 0.5
	var lone: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	_chk("b29 it anchors on the target SIDE's midpoint, not one slot",
			node.centre.distance_to(mid) < node.centre.distance_to(lone))


func _test_b29_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	_chk("b29 coverage reaches the measured level (%d)" % int(cov["playable"]),
			int(cov["playable"]) >= 769)
	for pair in [[81, "String Shot"], [122, "Lick"], [135, "Soft-Boiled"],
			[141, "Leech Life"], [155, "Bonemerang"], [186, "Sweet Kiss"],
			[208, "Milk Drink"], [212, "Mean Look"], [256, "Swallow"],
			[273, "Wish"], [281, "Yawn"], [294, "Tail Glow"],
			[309, "Meteor Mash"], [365, "Pluck"]]:
		_chk("b29 %s plays" % pair[1], _dispatcher.can_play_move(int(pair[0])))


# ── [M36D batch 30] ───────────────────────────────────────────────────────

func _test_b30_query_tasks_answer_on_the_right_register() -> void:
	# THE FINDING. Most query tasks answer on arg 7 -- the register batch 24
	# taught the VM to preserve across a command. But IsTargetPartner and
	# GetLycanrocForm answer on ARG 0, because upstream reads each with a
	# `jumpargeq 0 ...` on the very next line and `jumpargeq` does not reload
	# the registers. Moving either to arg 7 "for consistency" silently breaks
	# its consumer, and nothing else in this suite would notice.
	var stage := FakeStage.new()
	for symbol in ["AnimTask_RandomBool", "GetIsDoomDesireHitTurn",
			"AnimTask_IsHealingMove", "AnimTask_IsAttackerPlayerSide"]:
		var vm := _vm(stage)
		vm.args[0] = 123
		vm.args[AnimScriptVM.ARG_RET] = 123
		_registry.get_behavior(symbol).call(vm, {})
		_chk("b30 %s answers on arg 7 (%d)"
				% [symbol, vm.args[AnimScriptVM.ARG_RET]],
				vm.args[AnimScriptVM.ARG_RET] != 123)
		_chk("b30 %s ...and leaves arg 0 alone" % symbol, vm.args[0] == 123)
	for symbol in ["AnimTask_IsTargetPartner", "AnimTask_GetLycanrocForm"]:
		var vm2 := _vm(stage)
		vm2.args[0] = 123
		vm2.args[AnimScriptVM.ARG_RET] = 123
		_registry.get_behavior(symbol).call(vm2, {})
		_chk("b30 %s answers on ARG 0 (%d)" % [symbol, vm2.args[0]],
				vm2.args[0] != 123)
		_chk("b30 %s ...and leaves arg 7 alone" % symbol,
				vm2.args[AnimScriptVM.ARG_RET] == 123)


func _test_b30_query_answers_are_actually_correct() -> void:
	var stage := FakeStage.new()
	# Doom Desire: FALSE on the charge turns, TRUE on turn 2 only.
	for pair in [[0, 0], [1, 0], [2, 1], [3, 0]]:
		var vm := _vm(stage)
		vm.move_turn = int(pair[0])
		_registry.get_behavior("GetIsDoomDesireHitTurn").call(vm, {})
		_chk("b30 doom desire turn %d -> %d" % [pair[0], pair[1]],
				vm.args[AnimScriptVM.ARG_RET] == int(pair[1]))
	# IsHealingMove is INVERTED: damage > 0 means NOT healing.
	var heal := _vm(stage)
	heal.move_damage = 0
	_registry.get_behavior("AnimTask_IsHealingMove").call(heal, {})
	_chk("b30 zero damage reads as a healing move",
			heal.args[AnimScriptVM.ARG_RET] == 1)
	var hurt := _vm(stage)
	hurt.move_damage = 40
	_registry.get_behavior("AnimTask_IsHealingMove").call(hurt, {})
	_chk("b30 ...and real damage does NOT (the inverted read)",
			hurt.args[AnimScriptVM.ARG_RET] == 0)
	# Side polarity, both ways.
	var foe := FakeStage.new()
	foe.player_side = false
	var vf := _vm(foe)
	_registry.get_behavior("AnimTask_IsAttackerPlayerSide").call(vf, {})
	var vp := _vm(stage)
	_registry.get_behavior("AnimTask_IsAttackerPlayerSide").call(vp, {})
	_chk("b30 the side query reports 1 for the player and 0 for the foe",
			vp.args[AnimScriptVM.ARG_RET] == 1
			and vf.args[AnimScriptVM.ARG_RET] == 0)
	# RandomBool must genuinely vary rather than being a constant.
	var seen := {}
	for i in range(60):
		var vr := _vm(stage)
		_registry.get_behavior("AnimTask_RandomBool").call(vr, {})
		seen[vr.args[AnimScriptVM.ARG_RET]] = true
	_chk("b30 the coin flip produces both outcomes", seen.size() == 2)


func _test_b30_movement_waves_count_is_a_gate() -> void:
	# arg 2 == 0 destroys the sprite before it starts -- a gate, not a
	# duration. A port treating it as a minimum shows a wave that should
	# not be there.
	var off := FakeStage.new()
	var r0 := _spawn(off, "AnimMovementWaves", [0, 0, 0],
			"gMovementWavesSpriteTemplate")
	var n0: AnimSprite = r0["sprite"]
	_chk("b30 a repeat count of 0 ends the wave immediately",
			n0 == null or n0.is_finished())
	var on := FakeStage.new()
	var r1 := _spawn(on, "AnimMovementWaves", [0, 0, 2],
			"gMovementWavesSpriteTemplate")
	var n1: AnimSprite = r1["sprite"]
	if n1 == null:
		_chk("b30 movement wave spawned", false)
		return
	_chk("b30 ...while a nonzero count runs", not n1.is_finished())
	# arg 1 does double duty: it mirrors the spawn offset AND picks the cel.
	var flip := FakeStage.new()
	var r2 := _spawn(flip, "AnimMovementWaves", [0, 1, 2],
			"gMovementWavesSpriteTemplate")
	var n2: AnimSprite = r2["sprite"]
	if n2 != null:
		var c1: Vector2 = on.center_of(AnimStage.ANIM_ATTACKER)
		var c2: Vector2 = flip.center_of(AnimStage.ANIM_ATTACKER)
		_chk("b30 ...and arg 1 mirrors the spawn offset (%.1f vs %.1f)"
				% [n1.centre.x - c1.x, n2.centre.x - c2.x],
				signf(n1.centre.x - c1.x) != signf(n2.centre.x - c2.x))


func _test_b30_wring_out_orbits_a_whole_number_of_turns() -> void:
	# arg 2 is a DIVISOR of a full circle, not a duration: 256/arg2 per
	# frame. Read as a duration the ring crawls or blurs depending on the
	# value, and still orbits.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimMoveWringOut", [0, 0, 32, 1, 20],
			"gWringOutHandSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b30 wring out spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var start: Vector2 = node.centre
	var centre: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	var radius: float = start.distance_to(centre)
	_chk("b30 it starts on the ring, not at the centre (%.1f)" % radius,
			radius > 1.0)
	var max_dev := 0.0
	for i in range(31):
		_step(vm, 1)
		if is_instance_valid(node):
			max_dev = maxf(max_dev,
					absf(node.centre.distance_to(centre) - radius))
	_chk("b30 ...and stays on the ring throughout (max drift %.2f)" % max_dev,
			max_dev < radius * 0.15)
	# 32 steps of 256/32 = one full turn, so one spin must be over by then.
	_step(vm, 3)
	_chk("b30 ...completing exactly one spin in arg-2 frames",
			not is_instance_valid(node) or node.is_finished())


func _test_b30_punishment_joins_the_affine_impact_alias_chain() -> void:
	# The fourth verbatim duplicate of the same function, after
	# AnimGunkShotImpact (b24) and AnimForcePalm (b27).
	_chk("b30 AnimPunishment IS AnimGunkShotImpact, not a copy",
			_registry.get_behavior("AnimPunishment")
			== _registry.get_behavior("AnimGunkShotImpact"))
	_chk("b30 ...and so is AnimForcePalm, making three names one impl",
			_registry.get_behavior("AnimForcePalm")
			== _registry.get_behavior("AnimPunishment"))


func _test_b30_foresight_glass_mirrors_by_the_battler_it_sits_on() -> void:
	# The flip follows the BATTLER the glass is on, not the attacker -- so
	# the same task mirrors differently depending on its arg.
	var stage := FakeStage.new()
	var on_atk := _spawn(stage, "AnimForesightMagnifyingGlass", [0],
			"gForesightMagnifyingGlassSpriteTemplate")
	var s2 := FakeStage.new()
	var on_tgt := _spawn(s2, "AnimForesightMagnifyingGlass", [1],
			"gForesightMagnifyingGlassSpriteTemplate")
	var na: AnimSprite = on_atk["sprite"]
	var nt: AnimSprite = on_tgt["sprite"]
	if na == null or nt == null:
		_chk("b30 foresight glasses spawned", false)
		return
	_chk("b30 arg 0 selects which battler the glass sits on",
			na.centre.distance_to(stage.center_of(AnimStage.ANIM_ATTACKER))
			< 1.0
			and nt.centre.distance_to(s2.center_of(AnimStage.ANIM_TARGET))
			< 1.0)
	_chk("b30 ...and the two are mirrored differently",
			signf(na.scale.x) != signf(nt.scale.x))


func _test_b30_confetti_varies_per_particle() -> void:
	# Every parameter is a fresh draw. A port that fixed them gives a rigid
	# curtain of identical confetti, which still falls.
	var xs := {}
	# A FRESH stage per particle. `_spawn` returns the layer's FIRST
	# AnimSprite child, so spawning twelve onto one stage measures particle
	# zero twelve times and reports "2 distinct" however varied the draws
	# are -- the same trap batch 24's Hydro Cannon test hit.
	for i in range(12):
		var stage := FakeStage.new()
		var r := _spawn(stage, "AnimFlatterConfetti", [],
				"gFlatterConfettiSpriteTemplate")
		var node: AnimSprite = r["sprite"]
		if node == null:
			continue
		var start: Vector2 = node.centre
		# Sampled at 60 frames, not 10: the per-particle rates differ by
		# fractions of a pixel per frame, so an early sample rounds most
		# draws into the same bucket and the check passes for a port with
		# ONE fixed rate. Caught by the injection, not by the first run.
		_step(r["vm"], 60)
		xs[snappedf(node.centre.x - start.x, 1.0)] = true
	_chk("b30 confetti particles drift by differing amounts (%d distinct)"
			% xs.size(), xs.size() >= 4)


func _test_b30_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	_chk("b30 coverage reaches the measured level (%d)" % int(cov["playable"]),
			int(cov["playable"]) >= 781)
	# Torment and Happy Hour are deliberately NOT here: AnimTask_TormentAttacker
	# and AnimHappyHourCoinShower were read at Step 0 but not ported this
	# batch, and an aspirational move list is how a coverage test starts
	# lying. The first draft listed both and failed.
	for pair in [[165, "Struggle"], [193, "Foresight"], [353, "Doom Desire"],
			[367, "Acupressure"], [378, "Wring Out"], [386, "Punishment"],
			[788, "Population Bomb"]]:
		_chk("b30 %s plays" % pair[1], _dispatcher.can_play_move(int(pair[0])))


# ── [M36D batch 31] ───────────────────────────────────────────────────────

func _test_b31_helping_hand_clap_uses_screen_coords_and_converges() -> void:
	# Absolute screen coordinates (100/140, y 56), like batch 26's moon --
	# the hands meet in the MIDDLE of the screen, not beside either mon.
	var left := FakeStage.new()
	var rl := _spawn(left, "AnimHelpingHandClap", [0],
			"gHelpingHandClapSpriteTemplate")
	var right := FakeStage.new()
	var rr := _spawn(right, "AnimHelpingHandClap", [1],
			"gHelpingHandClapSpriteTemplate")
	var nl: AnimSprite = rl["sprite"]
	var nr: AnimSprite = rr["sprite"]
	if nl == null or nr == null:
		_chk("b31 helping hands spawned", false)
		return
	var scale: float = left.pixel_scale()
	_chk("b31 the left hand sits at screen x=100 (%.0f)" % nl.centre.x,
			absf(nl.centre.x - 100.0 * scale) < 1.0)
	_chk("b31 the right hand at x=140 (%.0f)" % nr.centre.x,
			absf(nr.centre.x - 140.0 * scale) < 1.0)
	_chk("b31 ...neither anchored on a battler",
			nl.centre.distance_to(left.center_of(AnimStage.ANIM_ATTACKER))
			> 20.0)
	# The two must move OPPOSITE ways -- data[7] is +1/-1 and drives both
	# axes, so they converge rather than drifting together.
	var l0: Vector2 = nl.centre
	var r0: Vector2 = nr.centre
	_step(rl["vm"], 6)
	_step(rr["vm"], 6)
	_chk("b31 ...and they move vertically in opposite directions (%.1f vs %.1f)"
			% [nl.centre.y - l0.y, nr.centre.y - r0.y],
			signf(nl.centre.y - l0.y) != signf(nr.centre.y - r0.y))
	_chk("b31 ...with the left hand mirrored", nl.scale.x < 0.0)


func _test_b31_helping_hand_movement_is_partner_relative_in_doubles() -> void:
	# Direction comes from the attacker's position RELATIVE TO ITS PARTNER
	# in doubles, falling back to the side rule only in singles.
	#
	# ⚠ THE FIRST DRAFT OF THIS TEST WAS VACUOUS. It used a player-side
	# stage, where FakeStage puts the partner to the RIGHT of the attacker --
	# so the partner rule and the side rule BOTH give -1 and the injection
	# that deleted the partner rule passed. The fixture has to be one where
	# the two rules DISAGREE, which is the opponent-side stage: the side rule
	# says +1 there while the partner rule still says -1.
	var foe := FakeStage.new()
	foe.player_side = false
	var vm := _vm(foe)
	var node: Control = foe.sprite_for(AnimStage.ANIM_ATTACKER)
	var base: Vector2 = node.position
	var me: Vector2 = foe.center_of(AnimStage.ANIM_ATTACKER)
	var ally: Vector2 = foe.center_of(AnimStage.ANIM_ATK_PARTNER)
	_chk("b31 the fixture genuinely separates the two rules",
			(me.x > ally.x) != (not foe.player_side))
	_registry.get_behavior("AnimTask_HelpingHandAttackerMovement").call(vm, {})
	_step(vm, 8)
	_chk("b31 the attacker leans (%.1f)" % (node.position.x - base.x),
			not node.position.is_equal_approx(base))
	var want: float = 1.0 if me.x > ally.x else -1.0
	_chk("b31 ...toward its PARTNER, not by the side rule",
			signf(node.position.x - base.x) == want)
	_step(vm, 20)
	_chk("b31 ...and returns", node.position.is_equal_approx(base))


func _test_b31_ingrain_root_never_moves_and_flickers_out() -> void:
	# The root's whole behavior is a flicker in its last ten frames. A port
	# that faded or slid it instead still disappears on time.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimIngrainRoot", [0, 0, 0, 0, 30],
			"gIngrainRootSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b31 ingrain root spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var at: Vector2 = node.centre
	var flickered_early := false
	for i in range(18):
		_step(vm, 1)
		if is_instance_valid(node) and not node.visible:
			flickered_early = true
	_chk("b31 the root does not move", node.centre.is_equal_approx(at))
	_chk("b31 ...and does NOT flicker before its last ten frames",
			not flickered_early)
	var flickered_late := false
	for i in range(11):
		_step(vm, 1)
		if is_instance_valid(node) and not node.visible:
			flickered_late = true
	_chk("b31 ...but does at the end", flickered_late)
	_step(vm, 4)
	_chk("b31 ...and then ends",
			not is_instance_valid(node) or node.is_finished())


func _test_b31_lock_on_wrapper_is_not_an_alias() -> void:
	# AnimLockOnMoveTarget CALLS AnimLockOnTarget after applying a quadrant
	# offset and flip. Registering them as one implementation would drop the
	# quadrant work, so identity here would be a BUG -- the opposite of the
	# alias assertions in batches 24/27/30.
	_chk("b31 lock-on move-target is NOT the same impl as lock-on target",
			_registry.get_behavior("AnimLockOnMoveTarget")
			!= _registry.get_behavior("AnimLockOnTarget"))
	# Four quadrants, four distinct corners around the target.
	var corners := {}
	for q in [1, 2, 3, 4]:
		var stage := FakeStage.new()
		var r := _spawn(stage, "AnimLockOnMoveTarget", [q],
				"gLockOnMoveTargetSpriteTemplate")
		var node: AnimSprite = r["sprite"]
		if node == null:
			continue
		var c: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
		corners["%d,%d" % [signi(int(node.centre.x - c.x)),
				signi(int(node.centre.y - c.y))]] = true
	_chk("b31 ...and its four quadrants land on four distinct corners (%d)"
			% corners.size(), corners.size() == 4)


func _test_b31_wood_hammer_waits_before_it_swings() -> void:
	# 37 frames of wind-up -- most of the animation. A hammer that swung
	# immediately still connects and still looks like a hammer.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimWoodHammerHammer", [],
			"gIvyCudgelFireSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b31 wood hammer spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
	_chk("b31 the hammer starts BEHIND the attacker",
			node.centre.x < atk.x)
	# It shivers during the wait but does not travel.
	var shivered := false
	for i in range(30):
		_step(vm, 1)
		if is_instance_valid(node) and node.offset.length() > 0.1:
			shivered = true
	_chk("b31 ...shivers while winding up", shivered)
	_chk("b31 ...and is still alive at frame 30 (the 37-frame wait)",
			is_instance_valid(node) and not node.is_finished())
	_step(vm, 25)
	_chk("b31 ...then swings and ends",
			not is_instance_valid(node) or node.is_finished())


func _test_b31_conversion2_inverts_conversions_signal() -> void:
	# Conversion's squares WAIT for arg 7 to kill them; Conversion 2's each
	# carry their own delay and then fly to the ATTACKER. Same family,
	# opposite control flow -- and the blend ramps the other way too.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimConversion2", [0, 0, 12],
			"gConversion2SpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b31 conversion2 square spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
	_chk("b31 it starts on the TARGET (Conversion starts on the attacker)",
			node.centre.distance_to(tgt) < node.centre.distance_to(atk))
	_step(vm, 10)
	_chk("b31 ...and holds still through its own delay",
			node.centre.distance_to(tgt) < 1.0)
	_step(vm, 30)
	_chk("b31 ...then flies to the attacker",
			node.centre.distance_to(atk) < node.centre.distance_to(tgt))
	# The blend ramp runs the opposite way to Conversion's.
	var vb := _vm(stage)
	_registry.get_behavior("AnimTask_Conversion2AlphaBlend").call(vb, {})
	_step(vb, 8)
	var eva2: int = int(vb.blend_context()["eva"])
	var vc := _vm(stage)
	_registry.get_behavior("AnimTask_ConversionAlphaBlend").call(vc, {})
	_step(vc, 8)
	var eva1: int = int(vc.blend_context()["eva"])
	_chk("b31 ...and the two blends ramp opposite ways (%d vs %d)"
			% [eva1, eva2], signi(eva1 - 8) != signi(eva2 - 8))


func _test_b31_perish_note2_is_never_drawn() -> void:
	# ⚠ It sets invisible on its first frame and exists ONLY as a timer.
	# Drawing it puts a stray note on screen that upstream never shows, and
	# no timing assertion would notice.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimPerishSongMusicNote2", [40],
			"gPerishSongMusicNote2SpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b31 perish note 2 spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	_chk("b31 the second perish note is INVISIBLE", not node.visible)
	var mon: Control = stage.sprite_for(AnimStage.ANIM_TARGET)
	var mod0: Color = mon.modulate
	_step(vm, 40)
	_chk("b31 ...and has not greyed the field yet",
			mon.modulate.is_equal_approx(mod0))
	_step(vm, 45)
	_chk("b31 ...greys it at 120 - arg0 frames",
			not mon.modulate.is_equal_approx(mod0))
	_step(vm, 85)
	_chk("b31 ...and restores it 80 frames later",
			mon.modulate.is_equal_approx(mod0))
	_chk("b31 ...never having become visible", not node.visible
			or node.is_finished())


func _test_b31_perish_note_sweeps_from_the_screen_centre() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimPerishSongMusicNote", [0, 0, 0],
			"gPerishSongMusicNoteSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b31 perish note spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var scale: float = stage.pixel_scale()
	_chk("b31 the note starts at screen x=120 (%.0f)" % node.centre.x,
			absf(node.centre.x - 120.0 * scale) < 1.0)
	var min_x := node.centre.x
	var max_x := node.centre.x
	var start_y := node.centre.y
	for i in range(90):
		_step(vm, 1)
		if is_instance_valid(node):
			min_x = minf(min_x, node.centre.x)
			max_x = maxf(max_x, node.centre.x)
	# Amplitude 100 out of a 240-wide screen is a near-full-width sweep.
	_chk("b31 ...and sweeps widely (%.0f px of %.0f)"
			% [max_x - min_x, 240.0 * scale],
			max_x - min_x > 100.0 * scale)
	_chk("b31 ...while sinking steadily", node.centre.y > start_y)


func _test_b31_partner_slides_move_the_partner_not_the_primary() -> void:
	# The whole point of the pair. A port that slid the primary would look
	# right in singles (where the partner is absent) and wrong in doubles.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	for i in range(5):
		vm.args[i] = [0, 20, 0, 0, 8][i]
	var partner: Control = stage.sprite_for(AnimStage.ANIM_ATK_PARTNER)
	var primary: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	var p0: Vector2 = partner.position
	var m0: Vector2 = primary.position
	_registry.get_behavior("SlideMonToOffsetPartner").call(vm, {})
	_step(vm, 8)
	_chk("b31 the PARTNER slides (%.1f)" % (partner.position.x - p0.x),
			not partner.position.is_equal_approx(p0))
	_chk("b31 ...and the primary attacker does not",
			primary.position.is_equal_approx(m0))
	# ...and the return leg puts it back.
	var vm2 := _vm(stage)
	vm2.args[0] = 0
	vm2.args[2] = 8
	_registry.get_behavior("SlideMonToOriginalPosPartner").call(vm2, {})
	_step(vm2, 9)
	_chk("b31 ...and the partner return leg restores it",
			partner.position.is_equal_approx(p0))


func _test_b31_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	_chk("b31 coverage reaches the measured level (%d)" % int(cov["playable"]),
			int(cov["playable"]) >= 795)
	for pair in [[176, "Conversion 2"], [195, "Perish Song"], [199, "Lock-On"],
			[270, "Helping Hand"], [275, "Ingrain"], [397, "Rock Polish"],
			[452, "Wood Hammer"], [607, "Hold Hands"]]:
		_chk("b31 %s plays" % pair[1], _dispatcher.can_play_move(int(pair[0])))
	# Sketch stays deferred with its scanline partner.
	_chk("b31 Sketch stays deferred (scanline pencil)",
			not _dispatcher.can_play_move(166))


# ── [M36D batch 32] ───────────────────────────────────────────────────────

func _test_b32_superpower_orb_holds_then_crosses() -> void:
	# 180 frames of charge -- three seconds, essentially the whole animation
	# -- then a 16-frame flight to the OTHER battler. Launching on spawn
	# still crosses correctly and loses the entire effect.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimSuperpowerOrb", [0],
			"gSuperpowerOrbSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b32 superpower orb spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
	var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	_chk("b32 the orb charges on the attacker",
			node.centre.distance_to(atk) < 1.0)
	_step(vm, 100)
	_chk("b32 ...and has not moved after 100 frames",
			node.centre.distance_to(atk) < 1.0)
	_step(vm, 95)
	_chk("b32 ...then crosses to the target",
			node.centre.distance_to(tgt) < node.centre.distance_to(atk))
	# arg 0 swaps which end it charges on and which it lands on.
	var s2 := FakeStage.new()
	var r2 := _spawn(s2, "AnimSuperpowerOrb", [1],
			"gSuperpowerOrbSpriteTemplate")
	var n2: AnimSprite = r2["sprite"]
	if n2 != null:
		_chk("b32 ...and arg 0 charges it on the target instead",
				n2.centre.distance_to(s2.center_of(AnimStage.ANIM_TARGET))
				< n2.centre.distance_to(s2.center_of(AnimStage.ANIM_ATTACKER)))


func _test_b32_devil_orbit_decays_and_reverses() -> void:
	# Two separate properties, and a plain circle satisfies neither: the
	# radius SHRINKS with age, and the phase runs forward then back.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimDevil", [0, 0], "gDevilSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b32 devil spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var start: Vector2 = node.centre
	var early := 0.0
	for i in range(12):
		_step(vm, 1)
		if is_instance_valid(node):
			early = maxf(early, node.centre.distance_to(start))
	var late := 0.0
	for i in range(50):
		_step(vm, 1)
		if is_instance_valid(node):
			late = maxf(late, node.centre.distance_to(start))
	_chk("b32 the devil orbits (%.1f)" % early, early > 1.0)
	_chk("b32 ...on a DECAYING radius, not a fixed one (%.1f -> %.1f)"
			% [early, late], late < early)
	# Solid in the middle, flickering at both ends.
	var s2 := FakeStage.new()
	var r2 := _spawn(s2, "AnimDevil", [0, 0], "gDevilSpriteTemplate")
	var n2: AnimSprite = r2["sprite"]
	var early_flicker := false
	for i in range(9):
		_step(r2["vm"], 1)
		if is_instance_valid(n2) and not n2.visible:
			early_flicker = true
	var mid_solid := true
	for i in range(40):
		_step(r2["vm"], 1)
		if is_instance_valid(n2) and not n2.visible:
			mid_solid = false
	_chk("b32 ...flickering early but solid in the middle",
			early_flicker and mid_solid)


func _test_b32_flying_notes_scale_the_two_axes_differently() -> void:
	# The offset is also the velocity, but x is divided by 5 while y is
	# multiplied by 8 and then divided by 5 -- so a note offset equally on
	# both axes still travels mostly vertically. Equal scaling gives a
	# diagonal, which still "flies".
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimFlyingMusicNotes", [0, 16, 16],
			"gFastFlyingMusicNotesSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b32 flying note spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var start: Vector2 = node.centre
	_step(vm, 30)
	var moved: Vector2 = node.centre - start
	_chk("b32 the note travels (%.1f, %.1f)" % [moved.x, moved.y],
			moved.length() > 1.0)
	_chk("b32 ...much further vertically than horizontally (%.1f vs %.1f)"
			% [absf(moved.y), absf(moved.x)],
			absf(moved.y) > absf(moved.x) * 3.0)


func _test_b32_bounce_ball_hides_the_attacker_without_leaking() -> void:
	# ⚠ The ball IS the mon. Hiding it raw would leave a Pokemon invisible
	# for the rest of the battle if the script ended early -- the leak class
	# rule (3) exists for -- so it must go through the VM's tracked path.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var ctx := {"template": "gBounceBallShrinkSpriteTemplate",
			"template_data": AnimData.template("gBounceBallShrinkSpriteTemplate"),
			"blend": {"eva": 16, "evb": 0}}
	_registry.get_behavior("AnimBounceBallShrink").call(vm, ctx)
	var mon: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	_chk("b32 the attacker is hidden while the ball is up", not mon.visible)
	# Abort the run mid-flight: the VM's own net must put it back.
	vm._finish()
	_chk("b32 ...and an aborted run restores it", mon.visible)


func _test_b32_dragon_rush_keys_on_the_targets_side() -> void:
	# Keyed on the TARGET's side, not the attacker's -- they differ for any
	# ally-targeting move, and the spin direction follows.
	var a := FakeStage.new()
	var ra := _spawn(a, "AnimDragonRush", [20, 0], "gDragonRushSpriteTemplate")
	var b := FakeStage.new()
	b.player_side = false
	var rb := _spawn(b, "AnimDragonRush", [20, 0], "gDragonRushSpriteTemplate")
	var na: AnimSprite = ra["sprite"]
	var nb: AnimSprite = rb["sprite"]
	if na == null or nb == null:
		_chk("b32 dragon rush spawned", false)
		return
	var ca: Vector2 = a.center_of(AnimStage.ANIM_TARGET)
	var cb: Vector2 = b.center_of(AnimStage.ANIM_TARGET)
	# ⚠ "The two sides differ" is NOT enough, and the first draft stopped
	# there. In singles the attacker and target are always on opposite
	# sides, so keying on either one produces a mirror -- the injection that
	# swapped to the attacker's side passed. The direction has to be pinned
	# ABSOLUTELY against source: `IsOnPlayerSide(gBattleAnimTarget)` is
	# FALSE for a player attacker, which takes the `x += args[0]` branch, so
	# the sprite must sit to the RIGHT of the target.
	_chk("b32 vs an opposing target the sprite sits RIGHT of it (%.1f)"
			% (na.centre.x - ca.x), na.centre.x > ca.x)
	_chk("b32 ...and vs a player-side target, LEFT of it (%.1f)"
			% (nb.centre.x - cb.x), nb.centre.x < cb.x)
	# ...and spin opposite ways, which the offset alone does not prove.
	#
	# ⚠ Measured on X, not Y, and the first draft got this wrong. The orbit
	# starts at phase 192 -- the sine's MINIMUM -- so stepping either
	# direction moves Y by the same amount, and a Y check reports "4.2 vs
	# 4.2" for a correctly-mirrored spin. Cosine is at a zero crossing there,
	# so X is the axis that separates the two directions.
	var a0: Vector2 = na.centre
	var b0: Vector2 = nb.centre
	_step(ra["vm"], 6)
	_step(rb["vm"], 6)
	_chk("b32 ...and spin in opposite directions (%.1f vs %.1f)"
			% [na.centre.x - a0.x, nb.centre.x - b0.x],
			signf(na.centre.x - a0.x) != signf(nb.centre.x - b0.x))


func _test_b32_overheat_flame_ellipse_is_three_fifths_tall() -> void:
	# The vertical amplitude is exactly 3/5 of the horizontal, so the spray
	# is a flattened ellipse. A shared amplitude gives a circle, which still
	# sprays outward.
	var widest := 0.0
	var tallest := 0.0
	for angle in [0, 32, 64, 96, 128, 160, 192, 224]:
		var stage := FakeStage.new()
		var r := _spawn(stage, "AnimOverheatFlame", [0, angle, 40, 20, 0],
				"gOverheatFlameSpriteTemplate")
		var node: AnimSprite = r["sprite"]
		if node == null:
			continue
		var start: Vector2 = node.centre
		_step(r["vm"], 18)
		widest = maxf(widest, absf(node.centre.x - start.x))
		tallest = maxf(tallest, absf(node.centre.y - start.y))
	_chk("b32 the overheat spray moves (%.1f x %.1f)" % [widest, tallest],
			widest > 1.0 and tallest > 1.0)
	_chk("b32 ...and is FLATTER than it is wide (3/5)", tallest < widest)
	# The speed arg also offsets the START, so a fast flame begins out from
	# the mon rather than at it.
	var slow := FakeStage.new()
	var rs := _spawn(slow, "AnimOverheatFlame", [0, 0, 40, 20, 0],
			"gOverheatFlameSpriteTemplate")
	var fast := FakeStage.new()
	var rf := _spawn(fast, "AnimOverheatFlame", [8, 0, 40, 20, 0],
			"gOverheatFlameSpriteTemplate")
	var ns: AnimSprite = rs["sprite"]
	var nf: AnimSprite = rf["sprite"]
	if ns != null and nf != null:
		var cs: Vector2 = slow.center_of(AnimStage.ANIM_ATTACKER)
		var cf: Vector2 = fast.center_of(AnimStage.ANIM_ATTACKER)
		_chk("b32 ...and the speed arg offsets the START (%.1f vs %.1f)"
				% [ns.centre.distance_to(cs), nf.centre.distance_to(cf)],
				nf.centre.distance_to(cf) > ns.centre.distance_to(cs) + 1.0)


func _test_b32_false_swipe_pair_is_not_an_alias() -> void:
	# Same family, different entry points: the positioned variant takes an
	# extra offset arg and plays cel variant 1.
	_chk("b32 the two false-swipe slices are separate impls",
			_registry.get_behavior("AnimFalseSwipeSlice")
			!= _registry.get_behavior("AnimFalseSwipePositionedSlice"))
	var a := FakeStage.new()
	var ra := _spawn(a, "AnimFalseSwipeSlice", [],
			"gFalseSwipeSliceSpriteTemplate")
	var b := FakeStage.new()
	var rb := _spawn(b, "AnimFalseSwipePositionedSlice", [24],
			"gFalseSwipePositionedSliceSpriteTemplate")
	var na: AnimSprite = ra["sprite"]
	var nb: AnimSprite = rb["sprite"]
	if na == null or nb == null:
		_chk("b32 false swipe slices spawned", false)
		return
	var ca: Vector2 = a.center_of(AnimStage.ANIM_TARGET)
	var cb: Vector2 = b.center_of(AnimStage.ANIM_TARGET)
	_chk("b32 ...and the positioned one honours its offset arg (%.1f vs %.1f)"
			% [na.centre.x - ca.x, nb.centre.x - cb.x],
			nb.centre.x - cb.x > na.centre.x - ca.x)


func _test_b32_geyser_rise_direction_follows_its_offset_sign() -> void:
	# arg 1 does double duty -- it offsets the spear AND its sign picks which
	# way the spear leans as it rises, so a row of them fans out.
	var left := FakeStage.new()
	var rl := _spawn(left, "SpriteCB_GeyserTarget", [0, -20, 0],
			"gFreezyFrostRisingSpearSpriteTemplate")
	var right := FakeStage.new()
	var rr := _spawn(right, "SpriteCB_GeyserTarget", [0, 20, 0],
			"gFreezyFrostRisingSpearSpriteTemplate")
	var nl: AnimSprite = rl["sprite"]
	var nr: AnimSprite = rr["sprite"]
	if nl == null or nr == null:
		_chk("b32 geysers spawned", false)
		return
	var l0: Vector2 = nl.centre
	var r0: Vector2 = nr.centre
	_step(rl["vm"], 10)
	_step(rr["vm"], 10)
	_chk("b32 both geysers RISE",
			nl.centre.y < l0.y and nr.centre.y < r0.y)
	_chk("b32 ...and lean opposite ways by their offset's sign (%.1f vs %.1f)"
			% [nl.centre.x - l0.x, nr.centre.x - r0.x],
			signf(nl.centre.x - l0.x) != signf(nr.centre.x - r0.x))


func _test_b32_coin_shower_ellipse_is_tall_and_narrow() -> void:
	# Amplitudes 16 and -70: the coins arc UP far more than they swing
	# sideways. A circular orbit is the obvious misreading and still looks
	# like coins circling.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimHappyHourCoinShower", [0, 0, 8, 0],
			"gHappyHourCoinShowerTemplate")
	var node: AnimSprite = r["sprite"]
	if node == null:
		_chk("b32 coin shower spawned", false)
		return
	var vm: AnimScriptVM = r["vm"]
	var start: Vector2 = node.centre
	var wide := 0.0
	var tall := 0.0
	for i in range(40):
		_step(vm, 1)
		if is_instance_valid(node):
			wide = maxf(wide, absf(node.centre.x - start.x))
			tall = maxf(tall, absf(node.centre.y - start.y))
	_chk("b32 the coins orbit (%.1f x %.1f)" % [wide, tall],
			wide > 1.0 and tall > 1.0)
	_chk("b32 ...on a TALL narrow ellipse, not a circle", tall > wide * 2.0)


func _test_b32_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	_chk("b32 coverage reaches the measured level (%d)" % int(cov["playable"]),
			int(cov["playable"]) >= 812)
	for pair in [[142, "Lovely Kiss"], [206, "False Swipe"], [340, "Bounce"],
			[407, "Dragon Rush"], [411, "Focus Blast"], [434, "Draco Meteor"],
			[603, "Happy Hour"], [686, "Freezy Frost"], [869, "Extreme Evoboost"]]:
		_chk("b32 %s plays" % pair[1], _dispatcher.can_play_move(int(pair[0])))


# ── [M36D batch 33] ───────────────────────────────────────────────────────

func _test_b33_thrash_pair_are_different_effects() -> void:
	# Same move, same name stem, DIFFERENT mechanisms: the horizontal is an
	# affine deformation, the vertical a plain displacement. Sharing one
	# implementation gives Thrash the same look twice.
	var h := FakeStage.new()
	var vh := _vm(h)
	var nh: Control = h.sprite_for(AnimStage.ANIM_ATTACKER)
	var hs: Vector2 = nh.scale
	var hp: Vector2 = nh.position
	_registry.get_behavior("AnimTask_ThrashMoveMonHorizontal").call(vh, {})
	_step(vh, 6)
	_chk("b33 the horizontal thrash DEFORMS the mon",
			not nh.scale.is_equal_approx(hs))
	# ⚠️ **THIS USED TO ASSERT "without displacing it" AND THAT ENCODED THE
	# PORT, NOT SOURCE.** `AnimTask_ThrashMoveMonHorizontal_Step` calls
	# `RunAffineAnimFromTaskData` (battle_anim_effects_2.c), which calls
	# `SetBattlerSpriteYOffsetFromYScale` on every frame it updates the matrix
	# (battle_anim_mons.c:1790) -- and `gThrashMoveMonAffineAnimCmds` has a
	# LIVE yScale column (+9/-20/+20/-9), so hardware moves this mon
	# vertically as it squashes. The old assertion passed only because the
	# port had no foot anchoring at all.
	#
	# The DISCRIMINATOR the test exists for survives intact, and is what is
	# asserted now: the horizontal is an affine deform whose only movement is
	# derived vertically from its own y-scale, while the vertical below is a
	# plain HORIZONTAL displacement with no deform. Sharing one implementation
	# would still be caught.
	_chk("b33 ...moving it only vertically, derived from its own y-scale",
			is_equal_approx(nh.position.x, hp.x)
			and not is_equal_approx(nh.position.y, hp.y))

	var v := FakeStage.new()
	var vv := _vm(v)
	var nv: Control = v.sprite_for(AnimStage.ANIM_ATTACKER)
	var vs: Vector2 = nv.scale
	var vp: Vector2 = nv.position
	_registry.get_behavior("AnimTask_ThrashMoveMonVertical").call(vv, {})
	_step(vv, 6)
	_chk("b33 the vertical thrash DISPLACES the mon",
			not nv.position.is_equal_approx(vp))
	_chk("b33 ...HORIZONTALLY, which is the half the other one never moves",
			not is_equal_approx(nv.position.x, vp.x))
	_chk("b33 ...without deforming it", nv.scale.is_equal_approx(vs))
	_step(vv, 20)
	_chk("b33 ...and returns it", nv.position.is_equal_approx(vp))
	# The affine table LOOPS twice -- 4 legs x 7 frames x 2 = 56, so it must
	# still be running at 40 and finished by 60.
	_step(vh, 34)
	_chk("b33 the horizontal thrash is still running at frame 40 (LOOP 2)",
			not nh.scale.is_equal_approx(hs))
	_step(vh, 25)
	_chk("b33 ...and restores after both loops", nh.scale.is_equal_approx(hs))


func _test_b33_facade_blend_cycles_rather_than_holding() -> void:
	# It steps a 24-entry ramp one per frame. A static tint is the obvious
	# misreading and looks like a perfectly reasonable colour flash.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = AnimStage.ANIM_ATTACKER
	vm.args[1] = 30
	var node: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	_registry.get_behavior("AnimTask_FacadeColorBlend").call(vm, {})
	_step(vm, 1)
	_chk("b33 the facade blend applies a tint", node.material != null)
	var seen := {}
	for i in range(20):
		_step(vm, 1)
		if node.material is ShaderMaterial:
			# The parameter is "tint" -- `_apply_blend_amount`'s own name.
			# The first draft read "blend_color", got null every frame, and
			# reported 0 distinct colours against a correctly cycling blend.
			var c: Variant = (node.material as ShaderMaterial) \
					.get_shader_parameter("tint")
			if c != null:
				seen[str(c)] = true
	_chk("b33 ...and CYCLES colours rather than holding one (%d)" % seen.size(),
			seen.size() >= 3)
	_step(vm, 20)
	_chk("b33 ...then clears the blend outright", node.material == null)


func _test_b33_shake_partner_scales_with_move_power() -> void:
	# It shakes the DEF PARTNER, not the target -- the reason the task exists
	# alongside the target-side one -- and the amplitude follows the move.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.move_power = 120
	for i in range(3):
		vm.args[i] = [0, 4, 20][i]
	var partner: Control = stage.sprite_for(AnimStage.ANIM_DEF_PARTNER)
	var target: Control = stage.sprite_for(AnimStage.ANIM_TARGET)
	var p0: Vector2 = partner.position
	var t0: Vector2 = target.position
	_registry.get_behavior(
			"AnimTask_ShakeTargetPartnerBasedOnMovePowerOrDmg").call(vm, {})
	_step(vm, 3)
	_chk("b33 the PARTNER shakes", not partner.position.is_equal_approx(p0))
	_chk("b33 ...and the target does not", target.position.is_equal_approx(t0))
	var strong: float = absf(partner.position.x - p0.x)
	# A weaker move must shake LESS -- that is the whole "based on power".
	var s2 := FakeStage.new()
	var v2 := _vm(s2)
	v2.move_power = 20
	for i in range(3):
		v2.args[i] = [0, 4, 20][i]
	var p2: Control = s2.sprite_for(AnimStage.ANIM_DEF_PARTNER)
	var q0: Vector2 = p2.position
	_registry.get_behavior(
			"AnimTask_ShakeTargetPartnerBasedOnMovePowerOrDmg").call(v2, {})
	_step(v2, 3)
	_chk("b33 ...and a weaker move shakes less (%.1f vs %.1f)"
			% [absf(p2.position.x - q0.x), strong],
			absf(p2.position.x - q0.x) < strong)
	_step(vm, 20)
	_chk("b33 ...and the partner is returned",
			partner.position.is_equal_approx(p0))


func _test_b33_skull_bash_step_is_fixed_point() -> void:
	# 0xC0 is 0.75 px per frame in 8.8, so eight frames move the mon SIX
	# pixels. Read as raw pixels it is 192 per frame -- the mon leaves the
	# field entirely, which no "did it move" assertion would catch.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[0] = 0
	var node: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	var base: Vector2 = node.position
	var scale: float = stage.pixel_scale()
	_registry.get_behavior("AnimTask_SkullBashPosition").call(vm, {})
	_step(vm, 8)
	var moved: float = absf(node.position.x - base.x) / scale
	_chk("b33 the wind-back moves about 6 px, not 1500 (%.1f)" % moved,
			moved > 3.0 and moved < 12.0)
	# arg 0 != 0 is the RETURN phase and must undo it.
	var vm2 := _vm(stage)
	vm2.args[0] = 1
	_registry.get_behavior("AnimTask_SkullBashPosition").call(vm2, {})
	_step(vm2, 9)
	_chk("b33 ...and the return phase puts the mon back",
			node.position.is_equal_approx(base))


func _test_b33_heat_wave_shoves_the_whole_target_side() -> void:
	# EVERY visible battler on the target's side, not just the target. A port
	# that moved only the target looks right in singles and wrong in doubles.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var tgt: Control = stage.sprite_for(AnimStage.ANIM_TARGET)
	var partner: Control = stage.sprite_for(AnimStage.ANIM_DEF_PARTNER)
	var atk: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	var t0: Vector2 = tgt.position
	var p0: Vector2 = partner.position
	var a0: Vector2 = atk.position
	_registry.get_behavior("AnimTask_MoveHeatWaveTargets").call(vm, {})
	_step(vm, 8)
	_chk("b33 the target is shoved", not tgt.position.is_equal_approx(t0))
	_chk("b33 ...and so is its PARTNER",
			not partner.position.is_equal_approx(p0))
	_chk("b33 ...while the attacker is untouched",
			atk.position.is_equal_approx(a0))
	_chk("b33 ...both the same way (a wave, not a scatter)",
			signf(tgt.position.x - t0.x) == signf(partner.position.x - p0.x))
	_step(vm, 30)
	_chk("b33 ...and both are returned",
			tgt.position.is_equal_approx(t0)
			and partner.position.is_equal_approx(p0))


func _test_b33_stockpile_counter_stub_is_bounded() -> void:
	# A documented stub, tested as one: it must answer on arg 7 (so a script
	# reading it is not left with a stale value) and must answer ZERO rather
	# than an invented number. If a later session threads the real counter
	# in, this is the assertion that should change.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[AnimScriptVM.ARG_RET] = 99
	_registry.get_behavior("AnimTask_GetStockpileCounter").call(vm, {})
	_chk("b33 the stockpile query writes arg 7",
			vm.args[AnimScriptVM.ARG_RET] != 99)
	_chk("b33 ...with the documented 0, not an invented value",
			vm.args[AnimScriptVM.ARG_RET] == 0)


func _test_b33_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	_chk("b33 coverage reaches the measured level (%d)" % int(cov["playable"]),
			int(cov["playable"]) >= 819)
	for pair in [[37, "Thrash"], [255, "Spit Up"], [257, "Heat Wave"],
			[263, "Facade"], [457, "Head Smash"]]:
		_chk("b33 %s plays" % pair[1], _dispatcher.can_play_move(int(pair[0])))
	# The deferred spawners, asserted as still-blocked so a partial port
	# cannot pass quietly. Water Sport (346) and Brine (362) were on this
	# list until batch 34 ported them; they are asserted as PLAYING there.
	for pair in [[348, "Leaf Blade"], [314, "Air Cutter"], [516, "Bestow"]]:
		_chk("b33 %s stays deferred (multi-phase spawner / item icon)"
				% pair[1], not _dispatcher.can_play_move(int(pair[0])))


# ── [M36D batch 34] ───────────────────────────────────────────────────────

func _test_b34_torment_cadence_is_not_uniform() -> void:
	# THE claim of this port. Upstream tests `data[1] <= 2` AFTER the
	# increment, so the extra 10-frame hold applies to bubbles 0 and 1 ONLY.
	# A reading that applies it to the first THREE (or to all six, or to
	# none) still produces six bubbles in the right places -- the cadence is
	# the only thing that separates the readings.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_TormentAttacker").call(vm, {})
	var spawn_frames: Array = []
	var seen := 0
	for f in range(120):
		_step(vm, 1)
		var n: int = _live_sprites(stage).size()
		while seen < n:
			spawn_frames.append(f)
			seen += 1
	_chk("b34 Torment makes SIX thought bubbles", spawn_frames.size() == 6)
	_chk("b34 ...on frames 0/22/44/56/68/80 (slow open, fast tail)",
			spawn_frames == [0, 22, 44, 56, 68, 80])


func _test_b34_torment_bubbles_alternate_and_converge() -> void:
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
	_registry.get_behavior("AnimTask_TormentAttacker").call(vm, {})
	_step(vm, 90)
	var bubbles: Array = _live_sprites(stage)
	_chk("b34 all six bubbles are still up", bubbles.size() == 6)
	if bubbles.size() != 6:
		return
	var alternates := true
	var converges := true
	var prev_mag := 1.0e9
	for i in range(6):
		var dx: float = bubbles[i].centre.x - atk.x
		var want_right: bool = (i % 2) == 0
		if (dx > 0.0) != want_right:
			alternates = false
		if (i % 2) == 0:
			if absf(dx) > prev_mag + 0.001:
				converges = false
			prev_mag = absf(dx)
	_chk("b34 bubbles alternate right/left of the attacker", alternates)
	_chk("b34 ...and each PAIR sits closer in than the last", converges)
	_chk("b34 ...climbing as they close (the last is above the first)",
			bubbles[5].centre.y < bubbles[0].centre.y)


func _test_b34_barrage_strobes_out_rather_than_fading() -> void:
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	_registry.get_behavior("AnimTask_BarrageBall").call(vm, {})
	var balls: Array = _live_sprites(stage)
	_chk("b34 Barrage makes one ball", balls.size() == 1)
	if balls.is_empty():
		return
	var ball: AnimSprite = balls[0]
	_step(vm, 16)
	_chk("b34 ...which lands BELOW the target's centre, not on it",
			ball.centre.y > tgt.y + 1.0)
	var alpha_before: float = ball.modulate.a
	var toggles := 0
	var was: bool = ball.visible
	for i in range(40):
		_step(vm, 1)
		if not is_instance_valid(ball):
			break
		if ball.visible != was:
			toggles += 1
			was = ball.visible
	_chk("b34 ...then STROBES out (visibility toggles, many times)",
			toggles >= 8)
	_chk("b34 ...without ever fading (alpha untouched)",
			is_instance_valid(ball) == false
			or is_equal_approx(ball.modulate.a, alpha_before))


func _test_b34_water_sport_sprays_away_from_the_user() -> void:
	# The sweep sign is `IsOnPlayerSide(attacker) ? 1 : -1`. Pinned
	# ABSOLUTELY on each side rather than "the two sides differ", which is
	# true under the inverted reading too.
	var out: Array = []
	for player in [true, false]:
		var stage := FakeStage.new()
		stage.player_side = player
		var vm := _vm(stage)
		var origin: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
		_registry.get_behavior("AnimTask_WaterSport").call(vm, {})
		_step(vm, 6)
		var drops: Array = _live_sprites(stage)
		if drops.is_empty():
			out.append(0.0)
			continue
		out.append(drops[0].centre.x - origin.x)
	_chk("b34 a PLAYER-side Water Sport sprays to the right",
			out.size() == 2 and float(out[0]) > 0.0)
	_chk("b34 ...and an OPPONENT-side one to the left",
			out.size() == 2 and float(out[1]) < 0.0)


func _test_b34_brine_rains_through_a_side_dependent_band() -> void:
	# Player side rains 0..40, opponent side 40..90. The bands do not merely
	# differ -- the opponent's STARTS where the player's ENDS, because the
	# opposing mon sits higher on screen.
	var tops: Array = []
	for player in [true, false]:
		var stage := FakeStage.new()
		stage.player_side = player
		var vm := _vm(stage)
		_registry.get_behavior("AnimTask_BrineRain").call(vm, {})
		_step(vm, 1)
		var drops: Array = _live_sprites(stage)
		tops.append(drops[0].centre.y if not drops.is_empty() else -1.0)
	# Asserted as a DELTA rather than two absolute y values: the drop has
	# already taken its first fall step by the time it is measurable, so the
	# absolute figures carry that step while the 40 px band offset does not.
	var scale: float = 1024.0 / 240.0
	_chk("b34 both sides genuinely spawn rain", tops.size() == 2
			and float(tops[0]) >= 0.0 and float(tops[1]) >= 0.0)
	_chk("b34 an OPPONENT-side Brine starts its band 40 px LOWER than a "
			+ "player-side one",
			tops.size() == 2
			and absf((float(tops[1]) - float(tops[0])) - 40.0 * scale) < 2.0)


func _test_b34_brine_stops_at_ten_drops() -> void:
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_BrineRain").call(vm, {})
	var peak := 0
	for i in range(200):
		_step(vm, 1)
		peak = maxi(peak, _live_sprites(stage).size())
	# Splats are spawned too, so the ceiling is not exactly 10 -- but the
	# task must stop, and it must not run away.
	_chk("b34 Brine's rain is bounded (10 drops, not an endless stream)",
			peak > 0 and peak <= 20)
	_chk("b34 ...and the task finishes", not vm.is_running()
			or _live_sprites(stage).size() == 0)


func _test_b34_ions_fall_across_the_sky_not_on_a_battler() -> void:
	# Two claims that a battler-anchored port would fail: the ions cover the
	# full screen WIDTH, and they never leave the TOP HALF.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[1] = 2
	vm.args[2] = 40
	_registry.get_behavior("AnimTask_CreateIons").call(vm, {})
	_step(vm, 40)
	var ions: Array = _live_sprites(stage)
	_chk("b34 Ion Deluge spawns a stream of ions", ions.size() >= 10)
	var scale: float = 1024.0 / 240.0
	var half: float = 80.0 * scale
	var all_high := true
	var lo := 1.0e9
	var hi := -1.0e9
	for s in ions:
		if s.centre.y > half + 1.0:
			all_high = false
		lo = minf(lo, s.centre.x)
		hi = maxf(hi, s.centre.x)
	_chk("b34 ...every one of them in the TOP HALF of the screen", all_high)
	_chk("b34 ...spread across the width, not stacked on a battler",
			hi - lo > 100.0 * scale)


func _test_b34_smokescreen_lands_down_right_of_the_target() -> void:
	# `+8, +8` -- both positive. A centred port, or one that read the offset
	# as a mon-pic correction and dropped it, fails both halves.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	_registry.get_behavior("AnimTask_SmokescreenImpact").call(vm, {})
	var puffs: Array = _live_sprites(stage)
	_chk("b34 Smokescreen makes an impact burst", puffs.size() == 1)
	if puffs.is_empty():
		return
	_chk("b34 ...offset DOWN and RIGHT of the target, not centred on it",
			puffs[0].centre.x > tgt.x + 1.0 and puffs[0].centre.y > tgt.y + 1.0)


func _test_b34_odor_sleuth_clones_are_mirror_images() -> void:
	# The two clones' x offsets are always exact negatives. THE 180-DEGREE
	# STARTING OFFSET is what carries that, NOT the opposite phase-step signs
	# -- injecting the same-direction misreading was tried and PASSED, because
	# only x is drawn and cos(t+128) == -cos(t) whichever way the phases walk.
	# So this pins the offset (the observable claim) and deliberately does not
	# pretend to test the step directions, which this port cannot see.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	var tgt: Control = stage.sprite_for(AnimStage.ANIM_TARGET)
	var home: Vector2 = tgt.position
	_registry.get_behavior("AnimTask_OdorSleuthMovement").call(vm, {})
	_chk("b34 Odor Sleuth makes TWO clones", _clone_count(stage) == 2)
	var clones: Array = []
	for child in stage.layer_node.get_children():
		if child.has_meta("_anim_trace"):
			clones.append(child)
	if clones.size() != 2:
		return
	var mirrored := true
	var ever_apart := false
	var single_visible := true
	for f in range(20):
		_step(vm, 1)
		var da: float = clones[0].position.x - home.x
		var db: float = clones[1].position.x - home.x
		if absf(da + db) > 1.0:
			mirrored = false
		if absf(da - db) > 4.0:
			ever_apart = true
		if clones[0].visible == clones[1].visible:
			single_visible = false
	_chk("b34 ...whose x offsets are exact negatives at every frame", mirrored)
	_chk("b34 ...and which genuinely separate (not both pinned at 0)",
			ever_apart)
	_chk("b34 ...with exactly ONE of the two on screen at a time",
			single_visible)


func _test_b34_odor_sleuth_shrinks_away_after_holding() -> void:
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_OdorSleuthMovement").call(vm, {})
	_step(vm, 50)
	_chk("b34 the clones are still up through the 60-frame hold",
			_clone_count(stage) == 2)
	_step(vm, 90)
	_chk("b34 ...then shrink to nothing and are cleaned up",
			_clone_count(stage) == 0)


func _test_b34_magical_leaf_ramps_into_each_colour_then_cuts() -> void:
	# 7 colours x 17 steps. Within a colour the strength walks 0..16; at the
	# boundary it SNAPS back to 0 with a new colour. A cross-fade port (the
	# plausible misreading of "cycle") never returns to 0 mid-run.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	# Borrow this batch's own one-shot burst to get a live anim sprite for
	# the ramp to act on.
	_registry.get_behavior("AnimTask_SmokescreenImpact").call(vm, {})
	var sprites: Array = _live_sprites(stage)
	if sprites.is_empty():
		_chk("b34 Magical Leaf has a sprite to tint", false)
		return
	var s: AnimSprite = sprites[0]
	var cycle_vm := _vm(stage)
	_registry.get_behavior("AnimTask_CycleMagicalLeafPal").call(cycle_vm, {})
	var amounts: Array = []
	var colours: Array = []
	for f in range(34):
		_step(cycle_vm, 1)
		var mat: ShaderMaterial = s.material as ShaderMaterial
		if mat == null:
			amounts.append(-1.0)
			colours.append(Color.BLACK)
			continue
		amounts.append(float(mat.get_shader_parameter("tint_amount")))
		colours.append(mat.get_shader_parameter("tint") as Color)
	_chk("b34 the blend ramps up within a colour",
			float(amounts[5]) > float(amounts[1]))
	_chk("b34 ...reaches full strength at the end of the colour",
			is_equal_approx(float(amounts[16]), 1.0))
	_chk("b34 ...then SNAPS back to zero rather than cross-fading",
			absf(float(amounts[17])) < 0.001)
	_chk("b34 ...on a DIFFERENT colour", colours[17] != colours[16])
	_chk("b34 ...and there are seven colours in the ramp",
			colours[0] != colours[17]
			and colours.size() == 34)
	_step(cycle_vm, 200)
	_chk("b34 ...with the tint cleared when the ramp is done",
			s.material == null)


func _test_b34_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	_chk("b34 coverage reaches the measured level (%d)" % int(cov["playable"]),
			int(cov["playable"]) >= 827)
	for pair in [[259, "Torment"], [140, "Barrage"], [346, "Water Sport"],
			[362, "Brine"], [569, "Ion Deluge"], [108, "Smokescreen"],
			[316, "Odor Sleuth"], [345, "Magical Leaf"]]:
		_chk("b34 %s plays" % pair[1], _dispatcher.can_play_move(int(pair[0])))
	# The spawners this batch deliberately left, asserted as still-blocked.
	# Eruption came off this list in b39 once its chain was read end to end.
	for pair in [[348, "Leaf Blade"], [314, "Air Cutter"], [139, "Poison Gas"]]:
		_chk("b34 %s stays deferred (stated reason)" % pair[1],
				not _dispatcher.can_play_move(int(pair[0])))


# ── [M36D batch 35] ───────────────────────────────────────────────────────

func _test_b35_mist_ball_ignores_its_spawn_offset() -> void:
	# THE claim. AnimThrowMistBall overwrites the sprite position with the
	# attacker's own coordinates BEFORE delegating to the shared translate
	# callback, so args 0/1 -- honoured by every OTHER user of that callback
	# -- are discarded. A port that just aliased the shared behavior would
	# spawn the ball at an offset and look correct in isolation.
	var out: Array = []
	for off in [0, 60]:
		var stage := FakeStage.new()
		var r := _spawn(stage, "AnimThrowMistBall", [off, off, 0, 0, 20],
				"gMistBallSpriteTemplate")
		out.append((r["sprite"] as AnimSprite).centre)
	_chk("b35 Mist Ball spawns identically regardless of args 0/1",
			out.size() == 2 and (out[0] as Vector2).is_equal_approx(out[1]))
	var stage2 := FakeStage.new()
	var r2 := _spawn(stage2, "AnimThrowMistBall", [0, 0, 0, 0, 20],
			"gMistBallSpriteTemplate")
	_chk("b35 ...at the attacker's own centre",
			(r2["sprite"] as AnimSprite).centre.is_equal_approx(
					stage2.center_of(AnimStage.ANIM_ATTACKER)))
	_step(r2["vm"], 20)
	_chk("b35 ...and it genuinely travels to the target",
			absf((r2["sprite"] as AnimSprite).centre.x
					- stage2.center_of(AnimStage.ANIM_TARGET).x) < 40.0
			or not is_instance_valid(r2["sprite"]))


func _test_b35_sky_drop_spawns_on_target_but_hides_the_attacker() -> void:
	# The asymmetry: it shares AnimFlyBallUp's step exactly, so the tempting
	# port is "Fly, for the target" -- which would hide the wrong Pokemon.
	var stage := FakeStage.new()
	var atk: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	var tgt: Control = stage.sprite_for(AnimStage.ANIM_TARGET)
	var r := _spawn(stage, "AnimSkyDropBallUp", [0, 0, 2, 128],
			"gSkyDropTargetFlyingTemplate")
	var ball: AnimSprite = r["sprite"]
	_chk("b35 Sky Drop's ball spawns on the TARGET",
			absf(ball.centre.x - stage.center_of(AnimStage.ANIM_TARGET).x)
					< absf(ball.centre.x
							- stage.center_of(AnimStage.ANIM_ATTACKER).x))
	_chk("b35 ...while the ATTACKER is the one hidden", not atk.visible)
	_chk("b35 ...and the target stays visible", tgt.visible)
	var y0: float = ball.centre.y
	_step(r["vm"], 8)
	_chk("b35 ...and it accelerates upward",
			not is_instance_valid(ball) or ball.centre.y < y0 - 1.0)
	(r["vm"] as AnimScriptVM)._finish()
	_chk("b35 ...with the hidden attacker restored when the run ends",
			atk.visible)


func _test_b35_will_o_wisp_orbs_drift_away_from_their_source() -> void:
	# Keyed on the ATTACKER's own side, not on the direction of travel toward
	# the target. Pinned ABSOLUTELY per side -- rule (13).
	var out: Array = []
	for player in [true, false]:
		var stage := FakeStage.new()
		stage.player_side = player
		var r := _spawn(stage, "AnimWillOWispOrb", [0, 0, 0],
				"gWillOWispOrbSpriteTemplate")
		var node: AnimSprite = r["sprite"]
		var x0: float = node.centre.x
		_step(r["vm"], 6)
		out.append(node.centre.x - x0)
	_chk("b35 a PLAYER-side Will-O-Wisp's orbs drift LEFT",
			out.size() == 2 and float(out[0]) < -1.0)
	_chk("b35 ...and an OPPONENT-side one's drift RIGHT",
			out.size() == 2 and float(out[1]) > 1.0)


func _test_b35_will_o_wisp_fire_spiral_grows() -> void:
	# THE claim of this behavior. Both ellipse amplitudes are ACCUMULATORS,
	# not constants -- the flame spirals outward rather than circling at a
	# fixed radius. A fixed-radius port is a different move entirely.
	var stage := FakeStage.new()
	var centre: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	var r := _spawn(stage, "AnimWillOWispFire", [0],
			"gWillOWispFireSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	var radii: Array = []
	var xs: Array = []
	var ys: Array = []
	for i in range(40):
		_step(r["vm"], 1)
		if not is_instance_valid(node):
			break
		var d: Vector2 = node.centre - centre
		radii.append(d.length())
		xs.append(absf(d.x))
		ys.append(absf(d.y))
	_chk("b35 Will-O-Wisp's flame starts near the target", radii.size() > 20
			and float(radii[0]) < 40.0)
	var late: float = 0.0
	for i in range(radii.size() - 8, radii.size()):
		late = maxf(late, float(radii[i]))
	var early: float = 0.0
	for i in range(mini(8, radii.size())):
		early = maxf(early, float(radii[i]))
	_chk("b35 ...and the spiral GROWS rather than circling at a fixed radius",
			late > early * 2.0)
	var max_x := 0.0
	var max_y := 0.0
	for i in range(xs.size()):
		max_x = maxf(max_x, float(xs[i]))
		max_y = maxf(max_y, float(ys[i]))
	_chk("b35 ...growing FASTER horizontally than vertically (0x180 vs 0xA0)",
			max_x > max_y)


func _test_b35_knock_off_tail_side_branch_is_not_a_mirror() -> void:
	# Source subtracts the x delta and reverses the orbit for a PLAYER-side
	# target, but ADDS the y delta either way. Reading it as a plain sign flip
	# on both axes puts the tail on the wrong side in one of the two cases.
	var dx: Array = []
	var dy: Array = []
	var spin: Array = []
	for player_attacker in [true, false]:
		var stage := FakeStage.new()
		stage.player_side = player_attacker
		var r := _spawn(stage, "AnimKnockOffAquaTail", [24, 12],
				"gAquaTailKnockOffSpriteTemplate")
		var node: AnimSprite = r["sprite"]
		var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
		# The spawn frame's own base, before the first orbit step.
		var d0: Vector2 = node.centre - tgt
		dx.append(d0.x)
		dy.append(d0.y)
		# Sampled on X: the orbit starts at phase 192, the sine's own
		# minimum, where stepping either direction moves Y identically --
		# rule (14). Cosine is at its steepest there, so X separates them.
		var a0: float = node.centre.x
		_step(r["vm"], 1)
		spin.append(node.centre.x - a0)
	_chk("b35 the x delta genuinely flips with the TARGET's side",
			dx.size() == 2 and signf(float(dx[0])) != signf(float(dx[1])))
	_chk("b35 ...while the y delta does NOT (both positive, not mirrored)",
			dy.size() == 2 and float(dy[0]) > 0.0 and float(dy[1]) > 0.0)
	_chk("b35 ...and the orbit runs the opposite way per side",
			spin.size() == 2
			and signf(float(spin[0])) != signf(float(spin[1])))


func _test_b35_zen_headbutt_offset_is_fixed_and_unmirrored() -> void:
	# +18 y is a constant in the code, not an argument, and not side-mirrored.
	#
	# ⚠️ THE "NOT MIRRORED" HALF IS NOT TESTED HERE, and injecting a mirror
	# PASSED. `FakeStage.facing_sign()` returns a fixed 1.0, so no stage
	# double in this suite can observe a facing flip -- the claim rests on the
	# source read alone. What IS pinned is the magnitude and the battler
	# selector. Rule (15): a green test must not be read as covering it.
	var offs: Array = []
	for player in [true, false]:
		var stage := FakeStage.new()
		stage.player_side = player
		var r := _spawn(stage, "AnimateZenHeadbutt", [1],
				"gZenHeadbuttSpriteTemplate")
		offs.append((r["sprite"] as AnimSprite).centre
				- stage.center_of(AnimStage.ANIM_TARGET))
	var scale: float = 1024.0 / 240.0
	_chk("b35 Zen Headbutt sits +18 px BELOW its battler",
			offs.size() == 2
			and absf((offs[0] as Vector2).y - 18.0 * scale) < 2.0)
	_chk("b35 ...identically on both sides (not mirrored)",
			offs.size() == 2
			and (offs[0] as Vector2).is_equal_approx(offs[1] as Vector2))
	var stage2 := FakeStage.new()
	var r2 := _spawn(stage2, "AnimateZenHeadbutt", [0],
			"gZenHeadbuttSpriteTemplate")
	_chk("b35 ...and arg 0 selects the ATTACKER instead",
			absf((r2["sprite"] as AnimSprite).centre.x
					- stage2.center_of(AnimStage.ANIM_ATTACKER).x) < 1.0)


func _test_b35_aqua_tail_spawns_on_either_battler() -> void:
	var out: Array = []
	for which in [0, 1]:
		var stage := FakeStage.new()
		var r := _spawn(stage, "AnimAquaTail", [0, 0, which, 0],
				"gAquaTailHitSpriteTemplate")
		out.append((r["sprite"] as AnimSprite).centre.x
				- stage.center_of(AnimStage.ANIM_ATTACKER if which == 0
						else AnimStage.ANIM_TARGET).x)
	_chk("b35 Aqua Tail's arg 2 genuinely selects the battler",
			out.size() == 2 and absf(float(out[0])) < 1.0
			and absf(float(out[1])) < 1.0)


func _test_b35_present_lands_below_the_target() -> void:
	var stage := FakeStage.new()
	var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	var r := _spawn(stage, "AnimPresent", [], "gPresentSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	_chk("b35 Present leaves the attacker",
			node.centre.is_equal_approx(
					stage.center_of(AnimStage.ANIM_ATTACKER)))
	var peak := node.centre.y
	for i in range(30):
		_step(r["vm"], 1)
		if not is_instance_valid(node):
			break
		peak = minf(peak, node.centre.y)
	_chk("b35 ...on a real ARC (it rises above both endpoints first)",
			peak < minf(stage.center_of(AnimStage.ANIM_ATTACKER).y, tgt.y) - 5.0)
	_step(r["vm"], 60)
	_chk("b35 ...and lands BELOW the target's centre, not on it",
			not is_instance_valid(node) or node.centre.y > tgt.y)


func _test_b35_present_heal_particle_drifts_linearly() -> void:
	# `y2 = velocity * age` -- no easing, no sine. Equal per-frame steps is
	# the whole claim; an eased port would fail it.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimPresentHealParticle", [0, 0, 3],
			"gPresentHealParticleSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	var ys: Array = []
	for i in range(6):
		_step(r["vm"], 1)
		ys.append(node.centre.y)
	var deltas: Array = []
	for i in range(1, ys.size()):
		deltas.append(float(ys[i]) - float(ys[i - 1]))
	var uniform := true
	for d in deltas:
		if absf(float(d) - float(deltas[0])) > 0.01:
			uniform = false
	_chk("b35 the heal particle drifts at a CONSTANT rate (linear, not eased)",
			deltas.size() >= 4 and uniform and absf(float(deltas[0])) > 1.0)


func _test_b35_twinkle_follows_its_selector() -> void:
	var out: Array = []
	for who in [AnimStage.ANIM_ATTACKER, AnimStage.ANIM_TARGET]:
		var stage := FakeStage.new()
		var r := _spawn(stage, "SpriteCB_TwinkleOnBattler", [0, 0, who],
				"gTargetTwinkleSpriteTemplate")
		out.append((r["sprite"] as AnimSprite).centre.x
				- stage.center_of(who).x)
	_chk("b35 the twinkle sits on whichever battler arg 2 names",
			out.size() == 2 and absf(float(out[0])) < 1.0
			and absf(float(out[1])) < 1.0)


func _test_b35_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	_chk("b35 coverage reaches the measured level (%d)" % int(cov["playable"]),
			int(cov["playable"]) >= 839)


# ── [M36D batch 36] ───────────────────────────────────────────────────────

func _test_b36_moongeist_and_power_shift_arc_to_the_attacker() -> void:
	# THE claim of the arc family. Five behaviors share
	# InitAnimArcTranslation; two of them aim at the USER, not the target,
	# because they are a charge and a self-buff. "Arc to the target" is the
	# natural reading and is wrong for exactly these two.
	for sym in ["SpriteCB_MoongeistCharge", "SpriteCB_PowerShiftBall"]:
		var tmpl := "gMoongeistBeamChargeTemplate" \
				if sym == "SpriteCB_MoongeistCharge" \
				else "gSpriteTemplate_PowerShiftDefenseBall"
		var stage := FakeStage.new()
		var r := _spawn(stage, sym, [0, 0, 0, 0, 12, 0], tmpl)
		var node: AnimSprite = r["sprite"]
		_step(r["vm"], 12)
		var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
		var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
		var landed: Vector2 = node.centre if is_instance_valid(node) else atk
		_chk("b36 %s converges on the ATTACKER, not the target" % sym,
				landed.distance_to(atk) < landed.distance_to(tgt))


func _test_b36_power_shift_mirrors_only_its_x_destination() -> void:
	# args[2] is negated for an opponent-side user; args[3] is not.
	var dx: Array = []
	var dy: Array = []
	for player in [true, false]:
		var stage := FakeStage.new()
		stage.player_side = player
		var r := _spawn(stage, "SpriteCB_PowerShiftBall", [0, 0, 30, 20, 10, 0],
				"gSpriteTemplate_PowerShiftDefenseBall")
		var node: AnimSprite = r["sprite"]
		_step(r["vm"], 10)
		var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
		var d: Vector2 = (node.centre if is_instance_valid(node) else atk) - atk
		dx.append(d.x)
		dy.append(d.y)
	_chk("b36 Power Shift's x destination flips with the user's side",
			dx.size() == 2 and signf(float(dx[0])) != signf(float(dx[1])))
	_chk("b36 ...while its y destination does NOT",
			dy.size() == 2 and float(dy[0]) > 0.0 and float(dy[1]) > 0.0)


func _test_b36_triple_arrow_aims_at_the_target_centre_exactly() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "SpriteCB_TripleArrowKick", [0, 0, 12, 0],
			"gSpriteTemplate_TripleArrowKick")
	var node: AnimSprite = r["sprite"]
	_step(r["vm"], 12)
	var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	_chk("b36 Triple Arrows lands on the target's exact centre (no offset)",
			not is_instance_valid(node) or node.centre.distance_to(tgt) < 6.0)


func _test_b36_glacial_lance_converges_on_the_whole_side() -> void:
	# In doubles the lance is thrown at the SIDE, so it converges on the
	# midpoint of both targets rather than on the selected one.
	var stage := FakeStage.new()
	var r := _spawn(stage, "SpriteCB_GlacialLance", [0, 0, 0, 0, 0, 0, 14],
			"gSpriteTemplate_GlacialLance")
	var node: AnimSprite = r["sprite"]
	_step(r["vm"], 14)
	var t0: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	var t1: Vector2 = stage.center_of(AnimStage.ANIM_DEF_PARTNER)
	var mid: Vector2 = (t0 + t1) * 0.5
	var landed: Vector2 = node.centre if is_instance_valid(node) else mid
	_chk("b36 Glacial Lance converges on the MIDPOINT of both targets",
			landed.distance_to(mid) < landed.distance_to(t0))
	_chk("b36 ...and it genuinely left the attacker",
			landed.distance_to(stage.center_of(AnimStage.ANIM_ATTACKER))
					> landed.distance_to(mid))


func _test_b36_surging_strikes_aims_at_the_target() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "SpriteCB_SurgingStrikes", [0, 0, 0, 0, 12, 0],
			"gSpriteTemplate_SurgingStrikesImpact")
	var node: AnimSprite = r["sprite"]
	_step(r["vm"], 12)
	var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
	var landed: Vector2 = node.centre if is_instance_valid(node) else tgt
	_chk("b36 Surging Strikes converges on the TARGET (the family's default)",
			landed.distance_to(tgt) < landed.distance_to(atk))


func _test_b36_elliptical_gust_is_flat() -> void:
	# Amplitudes are 32 in x and only 8 in y -- a horizontal swirl, not a
	# circle. A port that used one radius for both looks completely different.
	var stage := FakeStage.new()
	var base: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
	var r := _spawn(stage, "AnimEllipticalGustAttacker", [],
			"gBloomDoomHurricaneSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	var max_x := 0.0
	var max_y := 0.0
	for i in range(60):
		_step(r["vm"], 1)
		if not is_instance_valid(node):
			break
		max_x = maxf(max_x, absf(node.centre.x - base.x))
		max_y = maxf(max_y, absf(node.centre.y - base.y
				- 20.0 * (1024.0 / 240.0)))
	_chk("b36 the gust genuinely sweeps horizontally", max_x > 50.0)
	_chk("b36 ...on a FLAT ellipse (x amplitude far exceeds y)",
			max_x > max_y * 2.5)


func _test_b36_smelling_salt_sits_above_its_battler() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimSmellingSaltExclamation", [1, 20],
			"gSmellingSaltExclamationSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	var tgt: Control = stage.sprite_for(AnimStage.ANIM_TARGET)
	_chk("b36 the exclamation sits above the battler's TOP edge, not centre",
			node.centre.y <= tgt.position.y + 1.0)
	_chk("b36 ...horizontally centred on it",
			absf(node.centre.x - stage.center_of(AnimStage.ANIM_TARGET).x)
					< 1.0)
	# The clamp: a battler high on screen must not push it off the top.
	var stage2 := FakeStage.new()
	(stage2.sprite_for(AnimStage.ANIM_TARGET) as Control).position.y = -400.0
	var r2 := _spawn(stage2, "AnimSmellingSaltExclamation", [1, 20],
			"gSmellingSaltExclamationSpriteTemplate")
	_chk("b36 ...and is CLAMPED so it can never leave the top of the screen",
			(r2["sprite"] as AnimSprite).centre.y >= 0.0)


func _test_b36_lava_plume_flies_straight_not_in_an_orbit() -> void:
	# The name says orbit; the code samples its phase ONCE and never advances
	# it, so each ember flies a straight line on a fixed heading. The ellipse
	# is in the SPREAD of headings across embers, not in any one path.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimLavaPlumeOrbitScatter", [40],
			"gLavaPlumeSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	var pts: Array = []
	for i in range(6):
		_step(r["vm"], 1)
		if not is_instance_valid(node):
			break
		pts.append(node.centre)
	var uniform := true
	if pts.size() >= 4:
		var d0: Vector2 = (pts[1] as Vector2) - (pts[0] as Vector2)
		for i in range(2, pts.size()):
			var d: Vector2 = (pts[i] as Vector2) - (pts[i - 1] as Vector2)
			if not d.is_equal_approx(d0):
				uniform = false
	_chk("b36 a Lava Plume ember flies a STRAIGHT line at constant velocity",
			pts.size() >= 4 and uniform)
	# Different launch phases must genuinely produce different headings.
	var stage2 := FakeStage.new()
	var r2 := _spawn(stage2, "AnimLavaPlumeOrbitScatter", [130],
			"gLavaPlumeSpriteTemplate")
	_step(r["vm"], 0)
	_step(r2["vm"], 4)
	var b0: Vector2 = stage2.center_of(AnimStage.ANIM_ATTACKER)
	_chk("b36 ...and the launch phase genuinely selects its heading",
			((r2["sprite"] as AnimSprite).centre - b0).normalized()
					.distance_to(((pts[3] as Vector2)
							- stage.center_of(AnimStage.ANIM_ATTACKER))
							.normalized()) > 0.2)


func _test_b36_searing_shot_rock_refuses_an_invisible_battler() -> void:
	var stage := FakeStage.new()
	stage.set_battler_visible(AnimStage.ANIM_TARGET, false)
	var r := _spawn(stage, "SpriteCB_SearingShotRock", [0, 0, 0, 10, 1],
			"gSearingShotEruptionImpactTemplate")
	_step(r["vm"], 2)
	_chk("b36 Searing Shot's rock destroys itself rather than drawing on a "
			+ "hidden battler", _live_sprites(stage).size() == 0)
	var stage2 := FakeStage.new()
	var r2 := _spawn(stage2, "SpriteCB_SearingShotRock", [0, 0, 0, 10, 1],
			"gSearingShotEruptionImpactTemplate")
	_step(r2["vm"], 2)
	_chk("b36 ...but draws normally on a visible one",
			_live_sprites(stage2).size() == 1)


func _test_b36_upward_sprite_rises_at_constant_speed() -> void:
	var stage := FakeStage.new()
	var r := _spawn(stage, "SpriteCB_MoveSpriteUpwardsForDuration",
			[1, 0, 0, 3, 20], "gSpriteTemplate_BurningJealousyFireBuff")
	var node: AnimSprite = r["sprite"]
	var ys: Array = []
	for i in range(5):
		_step(r["vm"], 1)
		ys.append(node.centre.y)
	var deltas: Array = []
	for i in range(1, ys.size()):
		deltas.append(float(ys[i]) - float(ys[i - 1]))
	var uniform := true
	for d in deltas:
		if absf(float(d) - float(deltas[0])) > 0.01:
			uniform = false
	_chk("b36 the rising sprite moves UP at a constant rate",
			deltas.size() >= 3 and uniform and float(deltas[0]) < -1.0)


func _test_b36_query_tasks_answer_on_arg_zero() -> void:
	# ⚠️ RULE (12). Both write gBattleAnimArgs[0], NOT ARG_RET -- their
	# scripts read them with an immediately-following `jumpargeq 0`, which
	# does not reload the register file. Normalising them onto arg 7 would
	# break both consumers while looking tidier.
	for sym in ["AnimTask_TechnoBlast", "AnimTask_ShellSideArm"]:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		vm.args[0] = 99
		vm.args[AnimScriptVM.ARG_RET] = 99
		_registry.get_behavior(sym).call(vm, {})
		_chk("b36 %s answers on ARG 0" % sym, vm.args[0] == 0)
		_chk("b36 %s leaves ARG_RET alone" % sym,
				vm.args[AnimScriptVM.ARG_RET] == 99)


func _test_b36_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	_chk("b36 coverage reaches the measured level (%d)" % int(cov["playable"]),
			int(cov["playable"]) >= 851)
	for pair in [[746, "Surging Strikes"], [668, "Moongeist Beam"],
			[757, "Power Shift"], [771, "Triple Arrows"],
			[752, "Glacial Lance"], [545, "Searing Shot"],
			[546, "Techno Blast"], [729, "Shell Side Arm"],
			[436, "Lava Plume"], [358, "Wake-Up Slap"],
			[735, "Burning Jealousy"], [859, "Bloom Doom"]]:
		_chk("b36 %s plays" % pair[1], _dispatcher.can_play_move(int(pair[0])))


# ── [M36D batch 37] ───────────────────────────────────────────────────────

func _test_b37_rapid_spin_needs_no_scanline_surface() -> void:
	# The Step 0 correction this batch turns on: AnimRapidSpin is a plain
	# sprite behavior. It must run correctly with NO background layer at all,
	# which is what proves the five-batch-old "both are scanline" deferral
	# reason was inherited rather than checked.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimRapidSpin", [0, 0, -20, 20, 20, 3],
			"gRapidSpinSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	_chk("b37 Rapid Spin spawns without any background surface", node != null)
	var xs: Array = []
	for i in range(8):
		_step(r["vm"], 1)
		if not is_instance_valid(node):
			break
		xs.append(node.centre.x)
	var moved_both_ways := false
	if xs.size() >= 4:
		var up := false
		var down := false
		for i in range(1, xs.size()):
			if float(xs[i]) > float(xs[i - 1]):
				up = true
			elif float(xs[i]) < float(xs[i - 1]):
				down = true
		moved_both_ways = up and down
	_chk("b37 ...and genuinely oscillates horizontally", moved_both_ways)


func _test_b37_rapid_spin_ends_on_a_threshold_in_either_direction() -> void:
	# The crossing direction is captured ONCE at spawn from whether the
	# starting y is already past the threshold, so the same behavior serves a
	# rising AND a falling spin. Testing one direction misses half of it.
	var ended: Array = []
	# rising: start below (-20), climb (+3) toward +20 -> ends by exceeding it
	# falling: start above (+20), sink (-3) toward -20 -> ends by dropping under
	for cfg in [[-20, 20, 3], [20, -20, -3]]:
		var stage := FakeStage.new()
		var r := _spawn(stage, "AnimRapidSpin",
				[0, 0, int(cfg[0]), int(cfg[1]), 20, int(cfg[2])],
				"gRapidSpinSpriteTemplate")
		var node: AnimSprite = r["sprite"]
		var frames := -1
		for i in range(60):
			_step(r["vm"], 1)
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				frames = i + 1
				break
		ended.append(frames)
	# ⚠️ MEASURED, not merely "did it end". Injecting a FIXED crossing
	# direction (`y > threshold` for both) still ends the falling case -- on
	# frame 1, because it starts already past that test. Asserting only
	# "it ended" passed against that injection; the frame count is what
	# separates a captured direction from a hardcoded one. Rule (15).
	# Both legs travel 40 px at 3 px/frame, so ~13 frames each.
	_chk("b37 a RISING Rapid Spin ends ON its threshold, not immediately",
			ended.size() == 2 and int(ended[0]) >= 10 and int(ended[0]) <= 20)
	_chk("b37 a FALLING one ends on its own, OPPOSITE threshold, and takes "
			+ "just as long",
			ended.size() == 2 and int(ended[1]) >= 10 and int(ended[1]) <= 20)


func _test_b37_elevation_band_sweeps_upward() -> void:
	# The scanline surface. The band spans the mon and both its edges march
	# UP; a port that swept down, or held the band still, is the plausible
	# misreading and would look like a tear rather than a lift.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[1] = 4
	_registry.get_behavior("AnimTask_RapinSpinMonElevation").call(vm, {})
	var tops: Array = []
	var bottoms: Array = []
	for i in range(10):
		_step(vm, 1)
		var band: Vector3 = stage.band
		tops.append(band.x)
		bottoms.append(band.y)
	var top_rises := true
	for i in range(1, tops.size()):
		if float(tops[i]) > float(tops[i - 1]) + 0.001:
			top_rises = false
	_chk("b37 the elevation band's top edge sweeps UPWARD", top_rises
			and float(tops[tops.size() - 1]) < float(tops[0]))
	_chk("b37 ...starting BELOW the mon's centre",
			float(tops[0]) > stage.center_of(AnimStage.ANIM_ATTACKER).y)
	# The bottom edge is delayed 8 frames, so early on the band has real depth.
	_chk("b37 ...with its bottom edge lagging (the band has real depth)",
			float(bottoms[4]) > float(tops[4]))


func _test_b37_elevation_offset_is_a_shimmer_not_a_screen_jump() -> void:
	# +240 on a 256 px background WRAPS to -16. Porting the literal 240 would
	# displace the band nearly a full screen and read as a tearing bug.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[1] = 4
	_registry.get_behavior("AnimTask_RapinSpinMonElevation").call(vm, {})
	var offsets: Array = []
	for i in range(8):
		_step(vm, 1)
		offsets.append((stage.band as Vector3).z)
	var peak := 0.0
	for o in offsets:
		peak = maxf(peak, absf(float(o)))
	var scale: float = 1024.0 / 240.0
	_chk("b37 the band's offset is a ~16 px shimmer, not a ~240 px jump",
			peak > 1.0 and peak < 40.0 * scale)
	var toggled := false
	for i in range(1, offsets.size()):
		if not is_equal_approx(float(offsets[i]), float(offsets[i - 1])):
			toggled = true
	_chk("b37 ...and it alternates rather than holding", toggled)


func _test_b37_elevation_clears_its_band_when_done() -> void:
	# Leaving a displaced strip of background on screen after the move is the
	# same leak class rule (3) exists for.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	vm.args[1] = 6
	_registry.get_behavior("AnimTask_RapinSpinMonElevation").call(vm, {})
	_step(vm, 4)
	_chk("b37 the band is live mid-effect",
			(stage.band as Vector3).y > (stage.band as Vector3).x)
	_step(vm, 300)
	var band: Vector3 = stage.band
	# ⚠️ CHECKED AGAINST THE EXPLICIT RESET, not just a zero-height band.
	# The two edges converge on the same y by construction, so "bottom <= top"
	# is true whether or not anything cleared it -- that assertion passed
	# against an injection that removed the clear entirely. A real clear sets
	# the whole vector to zero, and the top edge can never reach 0 on its own
	# because it converges on a real on-screen y. Rule (15).
	_chk("b37 ...and is EXPLICITLY cleared once the sweep completes",
			band.is_equal_approx(Vector3.ZERO))
	_chk("b37 ...which the sweep alone could never produce",
			stage.center_of(AnimStage.ANIM_ATTACKER).y > 1.0)


func _test_b37_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	_chk("b37 coverage reaches the measured level (%d)" % int(cov["playable"]),
			int(cov["playable"]) >= 856)
	for pair in [[229, "Rapid Spin"], [789, "Ice Spinner"], [787, "Spin Out"],
			[794, "Mortal Spin"], [800, "Aqua Step"]]:
		_chk("b37 %s plays" % pair[1], _dispatcher.can_play_move(int(pair[0])))


# ── [M36D batch 38] ───────────────────────────────────────────────────────

func _test_b38_volt_switch_comes_back() -> void:
	# THE claim. Volt Switch is the move where the user leaves; a one-way arc
	# drops its whole signature. Source arcs to the target then immediately
	# arcs BACK over a fixed 20 frames.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimTask_VoltSwitch", [0, 0, 0, 0, 14, 0],
			"gVoltSwitchSpriteTemplate")
	var atk: Vector2 = stage.center_of(AnimStage.ANIM_ATTACKER)
	var tgt: Vector2 = stage.center_of(AnimStage.ANIM_TARGET)
	# Outbound leg.
	_step(r["vm"], 13)
	var out_far := 0.0
	for s in _live_sprites(stage):
		out_far = maxf(out_far, atk.distance_to((s as AnimSprite).centre))
	_chk("b38 Volt Switch's bolt travels away from the attacker",
			out_far > atk.distance_to(tgt) * 0.5)
	# Return leg: a second sprite is spawned at the apex and comes home.
	_step(r["vm"], 6)
	_chk("b38 ...and a RETURN leg is spawned once it arrives",
			_live_sprites(stage).size() >= 1)
	_step(r["vm"], 22)
	var home_near := 1.0e9
	for s in _live_sprites(stage):
		home_near = minf(home_near, atk.distance_to((s as AnimSprite).centre))
	_chk("b38 ...which ends back at the ATTACKER, not the target",
			_live_sprites(stage).is_empty() or home_near < out_far * 0.6)


func _test_b38_volt_switch_side_branches_do_different_work() -> void:
	# An opponent-side user negates args[2]; a player-side one instead nudges
	# the spawn 10 px down. Neither branch does the other's job, so a plain
	# mirror is wrong in both directions.
	var ys: Array = []
	for player in [true, false]:
		var stage := FakeStage.new()
		stage.player_side = player
		var r := _spawn(stage, "AnimTask_VoltSwitch", [0, 0, 30, 0, 14, 0],
				"gVoltSwitchSpriteTemplate")
		var node: AnimSprite = r["sprite"]
		ys.append(node.centre.y
				- stage.center_of(AnimStage.ANIM_ATTACKER).y)
	var scale: float = 1024.0 / 240.0
	_chk("b38 a PLAYER-side Volt Switch spawns 10 px lower",
			ys.size() == 2 and absf(float(ys[0]) - 10.0 * scale) < 2.0)
	_chk("b38 ...while an OPPONENT-side one does NOT drop at all",
			ys.size() == 2 and absf(float(ys[1])) < 2.0)


func _test_b38_superpower_rock_rises_then_takes_its_heading() -> void:
	# Two phases with DIFFERENT fixed-point scales -- 8.8 for the rise, 4.4
	# for the flight. The rock starts at screen bottom, not on the attacker.
	var stage := FakeStage.new()
	var r := _spawn(stage, "AnimSuperpowerRock", [60, 512, 0, 6],
			"gSuperpowerRockSpriteTemplate")
	var node: AnimSprite = r["sprite"]
	var scale: float = 1024.0 / 240.0
	_chk("b38 the rock starts at SCREEN BOTTOM, not on the attacker",
			absf(node.centre.y - 120.0 * scale) < 3.0)
	var ys: Array = []
	for i in range(6):
		_step(r["vm"], 1)
		if not is_instance_valid(node):
			break
		ys.append(node.centre.y)
	var rising := ys.size() >= 4
	for i in range(1, ys.size()):
		if float(ys[i]) >= float(ys[i - 1]):
			rising = false
	_chk("b38 ...rises during its rise phase", rising)
	# ⚠️ MEASURED PER-FRAME, not just "did x change". Injecting the WRONG
	# fixed-point scale for the flight phase (8.8 where source uses 4.4) still
	# moves it horizontally -- 16x too fast, straight off screen on frame one.
	# "It moved" passed against that; the step SIZE is what separates the two.
	# The heading is the raw battler gap applied at 4.4, so one frame of
	# flight is gap/16 -- tens of pixels, never hundreds.
	var gap: float = stage.center_of(AnimStage.ANIM_ATTACKER).distance_to(
			stage.center_of(AnimStage.ANIM_TARGET))
	var prev: Vector2 = node.centre if is_instance_valid(node) else Vector2.ZERO
	var flight_step := 0.0
	var moved_x := false
	for i in range(4):
		_step(r["vm"], 1)
		if not is_instance_valid(node):
			break
		var d: Vector2 = node.centre - prev
		if absf(d.x) > 0.5:
			moved_x = true
			flight_step = maxf(flight_step, d.length())
		prev = node.centre
	_chk("b38 ...then takes a HEADING and moves horizontally too", moved_x)
	_chk("b38 ...at the 4.4 flight scale (about gap/16 a frame, not gap)",
			flight_step > 0.0 and flight_step < gap / 4.0)


func _test_b38_slide_mon_returns_only_when_asked() -> void:
	# ⚠️ THE NAME OVER-PROMISES: "AndBack" happens only when args[5] is
	# nonzero. Source stores DestroyAnimSprite otherwise, leaving the mon
	# where it was slid to. Reading the name rather than the code would
	# cancel the displacement half the callers want.
	var rested: Array = []
	for back in [1, 0]:
		var stage := FakeStage.new()
		var mon: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
		var home: Vector2 = mon.position
		var vm := _vm(stage)
		vm.args[0] = 0
		vm.args[1] = 24
		vm.args[2] = 0
		vm.args[3] = 0
		vm.args[4] = 8
		vm.args[5] = back
		_registry.get_behavior("SlideMonToOffsetAndBack").call(vm, {})
		_step(vm, 4)
		var mid_moved: bool = not mon.position.is_equal_approx(home)
		_step(vm, 10)
		rested.append([mid_moved, mon.position.is_equal_approx(home)])
	_chk("b38 the mon genuinely slides while the effect runs",
			bool((rested[0] as Array)[0]) and bool((rested[1] as Array)[0]))
	_chk("b38 args[5] = 1 slides the mon AND brings it back",
			bool((rested[0] as Array)[1]))
	_chk("b38 args[5] = 0 leaves it displaced (the name over-promises)",
			not bool((rested[1] as Array)[1]))


func _test_b38_slide_mon_offset_is_restored_on_abort() -> void:
	# Rule (3): the controller sprite drags a BATTLER, so an aborted run must
	# not leave the Pokemon parked off its mark.
	var stage := FakeStage.new()
	var mon: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	var home: Vector2 = mon.position
	var vm := _vm(stage)
	vm.args[0] = 0
	vm.args[1] = 24
	vm.args[4] = 20
	vm.args[5] = 0
	_registry.get_behavior("SlideMonToOffsetAndBack").call(vm, {})
	_step(vm, 5)
	_chk("b38 the mon is displaced mid-slide",
			not mon.position.is_equal_approx(home))
	vm._finish()
	_chk("b38 ...and the VM's own net restores it when the run ends",
			mon.position.is_equal_approx(home))


func _test_b38_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	_chk("b38 coverage reaches the measured level (%d)" % int(cov["playable"]),
			int(cov["playable"]) >= 859)
	for pair in [[521, "Volt Switch"], [276, "Superpower"], [130, "Skull Bash"]]:
		_chk("b38 %s plays" % pair[1], _dispatcher.can_play_move(int(pair[0])))
	# The four spawners this batch deliberately left, asserted as still
	# blocked so a partial port cannot pass quietly.
	# b39 read Eruption's chain in full and ported it; the other three each
	# have their own named blocker recorded at the b39 section header.
	for pair in [[348, "Leaf Blade"], [314, "Air Cutter"], [139, "Poison Gas"]]:
		_chk("b38 %s stays deferred (named blocker, see b39)" % pair[1],
				not _dispatcher.can_play_move(int(pair[0])))


# ── [M36D batch 39] ───────────────────────────────────────────────────────

func _test_b39_eruption_crouches_before_it_erupts() -> void:
	# TWO INDEPENDENT HALVES a "spawner" framing hides. The attacker squashes
	# for 32 frames FIRST; the rocks only fly once that completes.
	var stage := FakeStage.new()
	var mon: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_EruptionLaunchRocks").call(vm, {})
	_step(vm, 16)
	_chk("b39 Eruption squashes the attacker before launching",
			mon.scale.y < 0.95)
	_chk("b39 ...WIDENING as it flattens (the inverted affine rule)",
			mon.scale.x > 1.0)
	_chk("b39 ...and no rock has flown yet", _live_sprites(stage).is_empty())
	_step(vm, 20)
	_chk("b39 ...then SEVEN rocks launch once the crouch completes",
			_live_sprites(stage).size() == 7)
	_chk("b39 ...with the attacker's own deformation restored",
			mon.scale.is_equal_approx(Vector2.ONE))


func _test_b39_eruption_jitters_the_attacker_both_ways() -> void:
	var stage := FakeStage.new()
	var mon: Control = stage.sprite_for(AnimStage.ANIM_ATTACKER)
	var home: float = mon.position.x
	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_EruptionLaunchRocks").call(vm, {})
	var left := false
	var right := false
	for i in range(20):
		_step(vm, 1)
		if mon.position.x < home - 1.0:
			left = true
		elif mon.position.x > home + 1.0:
			right = true
	_chk("b39 the attacker jitters BOTH ways during the crouch", left and right)


func _test_b39_eruption_rocks_all_launch_upward() -> void:
	# Every y in the speed table is negative -- the rocks all launch UP, and
	# the arc comes entirely from the gravity term. A port that read the
	# table as a spray would send some straight down.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_EruptionLaunchRocks").call(vm, {})
	_step(vm, 33)
	var rocks: Array = _live_sprites(stage)
	_chk("b39 seven rocks", rocks.size() == 7)
	var start_ys: Array = []
	for r in rocks:
		start_ys.append((r as AnimSprite).centre.y)
	_step(vm, 2)
	var all_up := rocks.size() == 7
	for i in range(rocks.size()):
		if not is_instance_valid(rocks[i]):
			continue
		if (rocks[i] as AnimSprite).centre.y >= float(start_ys[i]):
			all_up = false
	_chk("b39 ...and EVERY one of them launches upward", all_up)
	var xs: Dictionary = {}
	for r in rocks:
		if is_instance_valid(r):
			xs[snappedf((r as AnimSprite).centre.x, 0.5)] = true
	_chk("b39 ...on genuinely different headings, not one shared arc",
			xs.size() >= 5)


func _test_b39_eruption_gravity_is_quadratic_and_subpixel() -> void:
	# ⚠️ THE detail, and the one this test got WRONG TWICE.
	#
	# Gravity adds `stage * stage` every THIRD frame -- the amount ADDED grows
	# 1, 4, 9, 16..., so the acceleration is itself accelerating.
	#
	# Draft 1 compared consecutive per-frame deltas and demanded monotonic
	# growth. Gravity lands only every third frame, so correct code makes a
	# stair and that failed.
	# Draft 2 compared an early window against a late one. A CONSTANT gravity
	# (`+= 1` per tick) passed it, because constant gravity accelerates too --
	# uniformly. "It accelerates" cannot separate the two readings at all.
	#
	# What actually separates them is the SECOND difference: sample once per
	# gravity tick, take the velocity between samples, and require the CHANGE
	# in that velocity to grow. Quadratic gravity grows it; constant gravity
	# holds it flat.
	var stage := FakeStage.new()
	var vm := _vm(stage)
	_registry.get_behavior("AnimTask_EruptionLaunchRocks").call(vm, {})
	_step(vm, 33)
	var rocks: Array = _live_sprites(stage)
	if rocks.size() < 7:
		_chk("b39 gravity test has its rocks", false)
		return
	# Rock 1 is {-1,-1}, the slowest -- it stays on screen longest, so there
	# is room to measure a real curve.
	var rock: AnimSprite = rocks[1]
	var samples: Array = []
	for k in range(9):
		_step(vm, 3)                 # exactly one gravity tick per sample
		if not is_instance_valid(rock):
			break
		samples.append(rock.centre.y)
	var vel: Array = []
	for i in range(1, samples.size()):
		vel.append(float(samples[i]) - float(samples[i - 1]))
	var acc: Array = []
	for i in range(1, vel.size()):
		acc.append(float(vel[i]) - float(vel[i - 1]))
	var grows := acc.size() >= 4
	if grows:
		var first := float(acc[0])
		var last := float(acc[acc.size() - 1])
		grows = last > first + 0.001
	_chk("b39 gravity is QUADRATIC -- the acceleration itself accelerates",
			grows)
	_chk("b39 ...and the rock is genuinely still falling by the end",
			vel.size() >= 4 and float(vel[vel.size() - 1]) > 0.0)


func _test_b39_coverage() -> void:
	var ids: Array = []
	for id in range(1, 1000):
		if AnimData.script_for_move(id) != "":
			ids.append(id)
	var cov := _dispatcher.coverage(ids)
	_chk("b39 coverage reaches the measured level (%d)" % int(cov["playable"]),
			int(cov["playable"]) >= 860)
	_chk("b39 Eruption plays", _dispatcher.can_play_move(284))


# ─── [M36 review] the electric-family corrections ─────────────────────────
#
# Both of these were found by reading the reference beside the port rather
# than from a failing test, and neither is visible in Thunderbolt itself —
# the one script that uses all three behaviors passes a ZERO x offset to the
# two mirrored ones, so the sign error there is inert. They are asserted on
# fixtures built to make the divergence expressible, which is the only way
# this class of bug is observable at all.


# `AnimTask_ElectricBolt_Step` (battle_anim_electric.c:832) gives each of the
# five segments its OWN tile, and `AnimElectricBoltSegment` (:912) overrides
# the OAM to 8x16 or 16x16 by style. The port did neither: it called
# `_apply_anim_variant`, which is a silent no-op for this template (it has no
# anim table), so five identical 8x8 tiles were stacked 16px apart — a dotted
# line rather than a bolt.
#
# ⚠️ **THE FIFTH SEGMENT DELIBERATELY REUSES THE FIRST'S TILE**, because `r8`
# is a local reinitialised on every call and the `case 8` arm never adds to
# it. That is the assertion worth having: a plausible "advance the tile each
# time" implementation gives five DISTINCT tiles and passes any test that
# only checks the segments differ from each other.
func _test_rev_electric_bolt_segments_vary() -> void:
	for style in [0, 1]:
		var stage := FakeStage.new()
		var vm := _vm(stage)
		vm.args[2] = style
		_run_b5(vm, "AnimTask_ElectricBolt", "gElectricBoltSegmentSpriteTemplate")
		_step(vm, 12)
		var segs := _sprites_of(stage)
		if segs.size() != 5:
			_chk("rev bolt style %d spawns five segments (%d)"
					% [style, segs.size()], false)
			continue
		# Spawn order is child order, which is the order the tiles are keyed by.
		var regions: Array = []
		var sizes: Array = []
		for sp in segs:
			regions.append((sp as AnimSprite)._atlas.region)
			sizes.append((sp as AnimSprite).size)

		var want_size := Vector2(8, 16) if style == 0 else Vector2(16, 16)
		var all_sized := true
		for s in sizes:
			if not (s as Vector2).is_equal_approx(want_size):
				all_sized = false
		_chk("rev bolt style %d frames its segments %s, not the template's 8x8"
				% [style, want_size], all_sized)

		var distinct: Dictionary = {}
		for i in range(4):
			distinct[regions[i]] = true
		_chk("rev bolt style %d gives its first four segments four DIFFERENT "
				% style + "tiles (%d distinct)" % distinct.size(),
				distinct.size() == 4)
		_chk("rev bolt style %d wraps: the fifth segment reuses the first's tile"
				% style,
				(regions[4] as Rect2).is_equal_approx(regions[0] as Rect2))


# Upstream's mirroring idiom negates the x offset when the battler the sprite
# is ANCHORED TO is on the player's side — `IsOnPlayerSide(battler)` for
# `AnimSparkElectricityFlashing` (:761-776, anchor chosen by bit 15 of arg 7)
# and `IsOnPlayerSide(gBattleAnimTarget)` for `AnimThunderboltOrb` (:740).
# Both ported functions read the ATTACKER's side, which in singles is always
# the opposite one, so the offset landed mirrored rather than missing.
#
# ⚠️ **THE FIXTURE HAS TO PUT THE ANCHOR AND THE ATTACKER ON DIFFERENT SIDES,
# OR THE TWO RULES AGREE AND THE TEST PROVES NOTHING** (standing rule 13).
# Both cases below anchor on the TARGET with a player-side attacker, and the
# sign is asserted against the anchor's own centre — absolutely, not merely
# "the two sides differ", which would hold whichever battler you keyed on.
func _test_rev_electric_mirrors_key_on_the_anchor_battler() -> void:
	const X := 20

	# Spark: arg 7 bit 15 anchors it on the target; arg 0 is the x offset.
	var stage := FakeStage.new()
	stage.player_side = true          # attacker player-side => target is not
	var vm := _vm(stage)
	vm.args[0] = X
	vm.args[2] = 0                    # zero orbit radius, so only the base shows
	vm.args[3] = 40
	vm.args[7] = -32765               # 0x8003: anchor = target, modulus 3
	_run_b5(vm, "AnimSparkElectricityFlashing",
			"gSparkElectricityFlashingSpriteTemplate")
	_step(vm, 1)
	var spark: AnimSprite = _b5_last
	if spark == null:
		_chk("rev spark spawns", false)
	else:
		var anchor := stage.center_of(AnimStage.ANIM_TARGET)
		var dx: float = spark.centre.x - anchor.x
		_chk("rev spark anchored on the TARGET offsets +x when the target is "
				+ "NOT player-side (dx=%.1f)" % dx, dx > 0.0)

	# Orb: always anchored on the target; arg 1 is the x offset.
	var s2 := FakeStage.new()
	s2.player_side = true
	var vm2 := _vm(s2)
	vm2.args[0] = 44                  # lifetime
	vm2.args[1] = X
	vm2.args[3] = 3                   # flicker interval
	_run_b5(vm2, "AnimThunderboltOrb", "gThunderboltOrbSpriteTemplate")
	var orb: AnimSprite = _b5_last
	if orb == null:
		_chk("rev thunderbolt orb spawns", false)
	else:
		var anchor2 := s2.center_of(AnimStage.ANIM_TARGET)
		var dx2: float = orb.centre.x - anchor2.x
		_chk("rev thunderbolt orb offsets +x when the target is NOT "
				+ "player-side (dx=%.1f)" % dx2, dx2 > 0.0)

	# The other side, so neither assertion above can be passing on a constant.
	var s3 := FakeStage.new()
	s3.player_side = false            # attacker opponent-side => target IS player
	var vm3 := _vm(s3)
	vm3.args[0] = 44
	vm3.args[1] = X
	vm3.args[3] = 3
	_run_b5(vm3, "AnimThunderboltOrb", "gThunderboltOrbSpriteTemplate")
	var orb3: AnimSprite = _b5_last
	if orb3 == null:
		_chk("rev thunderbolt orb spawns on the mirrored side", false)
	else:
		var dx3: float = orb3.centre.x - s3.center_of(AnimStage.ANIM_TARGET).x
		_chk("rev thunderbolt orb NEGATES x when the target IS player-side "
				+ "(dx=%.1f)" % dx3, dx3 < 0.0)


# ─── [M36 review] Foot anchoring on the task-path affine runner ────────────
#
# `RunAffineAnimFromTaskData` calls `SetBattlerSpriteYOffsetFromYScale` every
# frame it touches the matrix (battle_anim_mons.c:1790), so a squashing mon
# SINKS onto its base instead of collapsing toward its own middle. The port
# had no equivalent, so all eleven task-path behaviours scaled about the M36P
# centre pivot and lifted the mon off the ground -- ~96 stage px at Facade's
# 1.6x, ~38 at Slack Off's 0.76x.
#
# ⚠️ **DERIVED FROM THE NEGATION, per standing rule (7).** The wrong version
# is not "no movement" -- it is "movement in the wrong DIRECTION", because a
# centre-pivot squash and a foot-anchored squash both move the drawn pixels.
# So the assertions pin the SIGN against the scale, which is the one thing the
# two implementations disagree about, and a fixture with a symmetric table
# would hide it.
func _test_rev_task_affine_keeps_the_feet_planted() -> void:
	# A pure squash (positive yScale delta on the task path = smaller sprite)
	# and a pure stretch, so the sign is unambiguous in both directions.
	var squash := [[0, 32, 0, 4]]
	var stretch := [[0, -32, 0, 4]]

	var a := FakeStage.new()
	var va := _vm(a)
	var na: Control = a.sprite_for(AnimStage.ANIM_ATTACKER)
	var rest: Vector2 = na.position
	AnimBehaviors._run_affine_cmds(va, na, squash, Callable(),
			AnimStage.ANIM_ATTACKER)
	_step(va, 3)
	_chk("rev a squash sinks the mon DOWN onto its base (dy=%.1f)"
			% (na.position.y - rest.y), na.position.y > rest.y)
	_chk("rev ...and does not slide it sideways",
			is_equal_approx(na.position.x, rest.x))

	var b := FakeStage.new()
	var vb := _vm(b)
	var nb: Control = b.sprite_for(AnimStage.ANIM_ATTACKER)
	var rest_b: Vector2 = nb.position
	AnimBehaviors._run_affine_cmds(vb, nb, stretch, Callable(),
			AnimStage.ANIM_ATTACKER)
	_step(vb, 3)
	_chk("rev a stretch lifts it UP by the same rule (dy=%.1f)"
			% (nb.position.y - rest_b.y), nb.position.y < rest_b.y)

	# It must come back, or the anchoring becomes a displacement leak of
	# exactly the kind rule (3) exists for.
	_step(va, 8)
	_chk("rev the anchor is released when the table ends",
			na.position.is_equal_approx(rest))

	# The formula itself, against source: y2 = (var - min(var*s, 128)) / 2,
	# var = 64 - 2*off, off = 0 when the species cannot be resolved.
	var pix := a.pixel_scale()
	_chk("rev the shift is source's own expression at s=0.5 (%.2f)"
			% AnimBehaviors._y_anchor_shift(64.0, 0.5, pix),
			is_equal_approx(AnimBehaviors._y_anchor_shift(64.0, 0.5, pix),
					16.0 * pix))
	_chk("rev ...zero at rest, so an unscaled behaviour is untouched",
			is_equal_approx(AnimBehaviors._y_anchor_shift(64.0, 1.0, pix), 0.0))
	# The clamp is var*s <= 128, which depends on var -- NOT a flat s <= 2.
	# At var=32 it bites at s=4, where a flat rule would still be scaling.
	_chk("rev ...and the cap is source's var-dependent one, not a flat 2x",
			is_equal_approx(AnimBehaviors._y_anchor_shift(32.0, 8.0, pix),
					AnimBehaviors._y_anchor_shift(32.0, 4.0, pix)))
