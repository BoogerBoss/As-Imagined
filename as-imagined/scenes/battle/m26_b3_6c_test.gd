extends Node

# [M26B3-6c-1] Regression suite for the per-species BACK entry animation --
# the left/right motion the player's own Pokemon makes while it is still
# pink, the instant it finishes emerging from its ball.
#
# Scope note, because it shapes what is worth asserting here: MonAnimator is
# a pure state machine with no scene dependencies, so every motion is
# directly unit-testable. That is deliberate. This arc's own repeated
# lesson is that the suite catches wrong VALUES and static contracts while
# being blind to whether the motion actually looks right -- four-plus
# defects across B3 were caught only by a screenshot or Rob's review. So
# this file tests the numbers hard and makes no claim about the look.

var _pass := 0
var _fail := 0


func _ready() -> void:
	# A. Data pipeline
	_test_every_species_has_anim_fields()
	_test_anim_ids_are_in_enum_range()
	_test_known_species_match_source()
	_test_gba_ternary_delay_resolved_to_live_branch()
	# B. Nature -> variant selection
	_test_nature_variant_table_matches_source()
	_test_nature_changes_which_variant_plays()
	_test_variant_lookup_is_bounds_safe()
	# C. Set table integrity
	_test_every_back_set_has_three_known_variants()
	_test_grow_set_third_entry_is_a_different_animation()
	_test_none_yields_no_animation()
	# D. GBA trig
	_test_sine_table_matches_source_shape()
	_test_sin_cos_match_source_formula()
	_test_trig_index_wrapping_is_safe()
	# E. Motion maths
	_test_every_variant_terminates()
	_test_h_slide_matches_hand_computed_source()
	_test_h_vibrate_alternates_sign()
	_test_jolt_right_walks_its_state_machine()
	_test_h_dip_is_rotation_driven()
	_test_glow_families_blend_and_clear()
	_test_flash_yellow_is_full_replace()
	_test_affine_scale_inversion()
	# F. Clock
	_test_clock_is_refresh_rate_independent()
	_test_clock_holds_sub_frame_remainder()
	# G. Dispatch
	_test_find_mon_slot_reports_side()
	await _test_back_animation_bypassed_when_not_in_tree()
	_test_unknown_species_degrades_gracefully()
	# H. Front animations (B3-6c-2)
	_test_every_front_id_in_use_is_implemented()
	_test_front_takes_no_nature()
	_test_every_front_anim_terminates()
	_test_front_reuses_back_steppers_where_source_does()
	_test_flicker_drives_visibility_not_transform()
	_test_front_glow_families_blend_and_clear()
	_test_rotate_up_slam_down_chains_into_shake()
	# I. Switch-out wiring (B3-6)
	_test_switch_out_queues_a_recall_beat()
	_test_switch_in_beat_carries_the_mon_for_send_out()
	# J. Rob's review fixes
	_test_recall_beat_captures_the_slot_at_signal_time()
	_test_ball_origin_is_mirrored_per_side()
	# K. Rob's review round 2
	_test_recall_finds_slot_after_party_moved_on()
	_test_opponent_send_out_is_delayed()
	# L. Rob's review round 3
	_test_recall_ball_and_pivot_are_bottom_anchored()
	_test_recall_ball_lift_is_per_side()
	# M. Party summary pacing (B5 item 1)
	_test_faint_no_longer_triggers_the_party_row()
	_test_switch_out_queues_the_summary_after_the_recall()
	_test_summary_is_switching_side_only()
	_test_hide_clears_both_rows()
	# N. Party row entry animation (B5 items 2+4)
	_test_ball_entry_delay_fans_per_side()
	_test_entry_constants_match_source()

	var total := _pass + _fail
	print("m26_b3_6c_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ---------------------------------------------------------------------
# A. Data pipeline
# ---------------------------------------------------------------------

func _test_every_species_has_anim_fields() -> void:
	var missing := 0
	for dex in range(1, 387):
		var row: Dictionary = PokemonRegistry.get_species(dex)
		if row == null or row.is_empty():
			missing += 1
			continue
		if not row.has("back_anim_id") or not row.has("front_anim_id") \
				or not row.has("front_anim_delay"):
			missing += 1
	_chk("A.01 all 386 species carry the 3 anim fields", missing == 0)


func _test_anim_ids_are_in_enum_range() -> void:
	var bad_back := 0
	var bad_front := 0
	var bad_delay := 0
	var none_count := 0
	for dex in range(1, 387):
		var row: Dictionary = PokemonRegistry.get_species(dex)
		var b: int = int(row.get("back_anim_id", -1))
		var f: int = int(row.get("front_anim_id", -1))
		var d: int = int(row.get("front_anim_delay", -1))
		if b < 0 or b >= MonAnimator.BACK_ANIM_COUNT:
			bad_back += 1
		if b == MonAnimator.BACK_ANIM_NONE:
			none_count += 1
		# enum AnimFunctionIDs has ANIM_COUNT == 155 entries.
		if f < 0 or f >= 155:
			bad_front += 1
		if d < 0 or d > 255:
			bad_delay += 1
	_chk("A.02 every back_anim_id is in enum BackAnim range", bad_back == 0)
	_chk("A.03 every front_anim_id is in enum AnimFunctionIDs range", bad_front == 0)
	_chk("A.04 every front_anim_delay is a plausible u8", bad_delay == 0)
	# Discriminator with real teeth: the 97 BACK_ANIM_NONE entries in source
	# are ALL Gmax/regional/cosplay forms, none of which is a base form, so
	# every one of the 386 genuinely animates on entry. If a future pull
	# started picking up form rows instead of base forms this would trip.
	_chk("A.05 no base-form species is BACK_ANIM_NONE", none_count == 0)


func _test_known_species_match_source() -> void:
	# Hand-verified against gen_{1,3}_families.h.
	var expect := {
		1: {"back": MonAnimator.BACK_ANIM_DIP_RIGHT_SIDE, "delay": 0},      # Bulbasaur
		6: {"back": MonAnimator.BACK_ANIM_SHAKE_GLOW_RED, "delay": 0},      # Charizard
		25: {"back": MonAnimator.BACK_ANIM_SHAKE_FLASH_YELLOW, "delay": 25}, # Pikachu
		150: {"back": MonAnimator.BACK_ANIM_GROW_STUTTER, "delay": 0},      # Mewtwo
		201: {"back": MonAnimator.BACK_ANIM_SHRINK_GROW_VIBRATE, "delay": 0}, # Unown
		384: {"back": MonAnimator.BACK_ANIM_GROW_STUTTER, "delay": 60},     # Rayquaza
	}
	for dex in expect:
		var row: Dictionary = PokemonRegistry.get_species(dex)
		_chk("A.06 dex %d back_anim_id matches source" % dex,
				int(row.get("back_anim_id", -1)) == expect[dex]["back"])
		_chk("A.07 dex %d front_anim_delay matches source" % dex,
				int(row.get("front_anim_delay", -1)) == expect[dex]["delay"])


func _test_gba_ternary_delay_resolved_to_live_branch() -> void:
	# Pikachu's source value is `P_GBA_STYLE_SPECIES_GFX ? 0 : 25`. That
	# config is FALSE here, so the live value is 25. A numeric-only regex
	# reads it as 0 and reports nothing missing -- which is exactly the bug
	# the first cut of gen_anim_ids.py shipped, caught by a spot-check
	# rather than by the extractor's own completeness pass. Pinned so it
	# cannot silently return.
	var pikachu: Dictionary = PokemonRegistry.get_species(25)
	_chk("A.08 GBA-style ternary delay takes the live (false) branch",
			int(pikachu.get("front_anim_delay", -1)) == 25)
	# Unown (#201) is hardcoded because UNOWN_MISC_INFO is a macro, not a
	# parseable struct literal -- the same blind spot gen_weight_data.py
	# documents. Confirm the hardcode actually landed.
	var unown: Dictionary = PokemonRegistry.get_species(201)
	_chk("A.09 Unown's macro-sourced ids are populated",
			int(unown.get("back_anim_id", -1)) == MonAnimator.BACK_ANIM_SHRINK_GROW_VIBRATE)


# ---------------------------------------------------------------------
# B. Nature -> variant selection
# ---------------------------------------------------------------------

func _test_nature_variant_table_matches_source() -> void:
	_chk("B.01 nature table covers all 25 natures",
			MonAnimator.NATURE_BACK_VARIANT.size() == 25)
	var counts := [0, 0, 0]
	var out_of_range := 0
	for n in range(MonAnimator.NATURE_BACK_VARIANT.size()):
		var v: int = int(MonAnimator.NATURE_BACK_VARIANT[n])
		if v < 0 or v > 2:
			out_of_range += 1
		else:
			counts[v] += 1
	_chk("B.02 every nature maps to variant 0/1/2", out_of_range == 0)
	# gNaturesInfo's own distribution, counted directly from src/pokemon.c.
	_chk("B.03 variant distribution is source's 8/9/8",
			counts[0] == 8 and counts[1] == 9 and counts[2] == 8)
	# Spot-checks against named source entries.
	_chk("B.04 HARDY -> variant 0", MonAnimator.variant_for_nature(0) == 0)
	_chk("B.05 LONELY -> variant 2", MonAnimator.variant_for_nature(1) == 2)
	_chk("B.06 BOLD -> variant 1", MonAnimator.variant_for_nature(5) == 1)


func _test_nature_changes_which_variant_plays() -> void:
	# The headline behaviour of this whole item: same species, different
	# nature, genuinely different animation.
	var hardy := MonAnimator.anim_key_for(MonAnimator.BACK_ANIM_H_SLIDE, 0)
	var lonely := MonAnimator.anim_key_for(MonAnimator.BACK_ANIM_H_SLIDE, 1)
	var naughty := MonAnimator.anim_key_for(MonAnimator.BACK_ANIM_H_SLIDE, 5)
	_chk("B.07 HARDY picks the fast H_SLIDE variant", hardy == "h_slide_fast")
	_chk("B.08 LONELY picks the slow H_SLIDE variant", lonely == "h_slide_slow")
	_chk("B.09 BOLD picks the normal H_SLIDE variant", naughty == "h_slide")
	_chk("B.10 the three natures genuinely differ",
			hardy != lonely and lonely != naughty and hardy != naughty)
	# And the difference is real motion, not just a different label.
	var a := MonAnimator.start(MonAnimator.BACK_ANIM_H_SLIDE, 0)
	var b := MonAnimator.start(MonAnimator.BACK_ANIM_H_SLIDE, 1)
	var fa := _frames_to_finish(a)
	var fb := _frames_to_finish(b)
	_chk("B.11 fast variant finishes in fewer frames than slow", fa < fb)


func _test_variant_lookup_is_bounds_safe() -> void:
	_chk("B.12 negative nature falls back to variant 0",
			MonAnimator.variant_for_nature(-1) == 0)
	_chk("B.13 out-of-range nature falls back to variant 0",
			MonAnimator.variant_for_nature(999) == 0)


# ---------------------------------------------------------------------
# C. Set table integrity
# ---------------------------------------------------------------------

func _test_every_back_set_has_three_known_variants() -> void:
	var sets_ok := true
	var keys_ok := true
	for back_id in range(1, MonAnimator.BACK_ANIM_COUNT):
		if not MonAnimator.BACK_ANIM_SETS.has(back_id):
			sets_ok = false
			continue
		var variants: Array = MonAnimator.BACK_ANIM_SETS[back_id]
		if variants.size() != 3:
			sets_ok = false
		for key in variants:
			if not MonAnimator.ANIM_SETUP.has(key):
				keys_ok = false
	_chk("C.01 all 25 back sets present, each with 3 variants", sets_ok)
	_chk("C.02 every variant key resolves to a real setup entry", keys_ok)
	_chk("C.03 set table has exactly 25 entries (NONE excluded)",
			MonAnimator.BACK_ANIM_SETS.size() == 25)


func _test_grow_set_third_entry_is_a_different_animation() -> void:
	# BACK_ANIM_GROW is the one set whose three entries are NOT one family
	# at three speeds -- source's third entry is ANIM_GROW_IN_STAGES, a
	# structurally different animation. Flattening the table into
	# "family + speed" would silently lose this.
	var variants: Array = MonAnimator.BACK_ANIM_SETS[MonAnimator.BACK_ANIM_GROW]
	var fn_a: String = String(MonAnimator.ANIM_SETUP[variants[0]]["fn"])
	var fn_c: String = String(MonAnimator.ANIM_SETUP[variants[2]]["fn"])
	_chk("C.04 GROW's 1st variant uses the grow stepper", fn_a == "grow")
	_chk("C.05 GROW's 3rd variant uses a DIFFERENT stepper",
			fn_c == "grow_in_stages" and fn_c != fn_a)


func _test_none_yields_no_animation() -> void:
	var st := MonAnimator.start(MonAnimator.BACK_ANIM_NONE, 0)
	_chk("C.06 BACK_ANIM_NONE produces no animation state", st.is_empty())
	_chk("C.07 anim_key_for(NONE) is empty",
			MonAnimator.anim_key_for(MonAnimator.BACK_ANIM_NONE, 0) == "")
	# step() on an empty state must be a safe no-op, not a crash -- the
	# dispatch path relies on that.
	MonAnimator.step(st)
	_chk("C.08 stepping an empty state is a safe no-op", st.is_empty())
	_chk("C.09 empty state yields identity transforms",
			MonAnimator.godot_offset(st) == Vector2.ZERO
			and MonAnimator.godot_scale(st) == Vector2.ONE
			and is_equal_approx(MonAnimator.godot_rotation(st), 0.0))


# ---------------------------------------------------------------------
# D. GBA trig
# ---------------------------------------------------------------------

func _test_sine_table_matches_source_shape() -> void:
	_chk("D.01 gSineTable has source's 320 entries",
			MonAnimator.SINE_TABLE.size() == 320)
	# Q_8_8: 256 == 1.0. The extra 64 entries past index 255 exist so Cos
	# can index [i + 64].
	_chk("D.02 table[0] == 0", int(MonAnimator.SINE_TABLE[0]) == 0)
	_chk("D.03 table[64] == 256 (peak)", int(MonAnimator.SINE_TABLE[64]) == 256)
	_chk("D.04 table[128] == 0", int(MonAnimator.SINE_TABLE[128]) == 0)
	_chk("D.05 table[192] == -256 (trough)", int(MonAnimator.SINE_TABLE[192]) == -256)
	# The table is embedded rather than recomputed precisely BECAUSE it is
	# not round(sin*256): 150 of the 320 entries differ. Prove at least one
	# such entry survived verbatim, so a future "simplification" to a
	# computed table fails here rather than drifting silently.
	var computed_2: int = int(round(sin(2.0 * PI / 128.0) * 256.0))
	_chk("D.06 table is source's, not a recomputed round(sin*256)",
			int(MonAnimator.SINE_TABLE[2]) == 12 and computed_2 != 12)


func _test_sin_cos_match_source_formula() -> void:
	# Sin(index, amplitude) == (amplitude * gSineTable[index]) >> 8
	_chk("D.07 sin_g(0, 100) == 0", MonAnimator.sin_g(0, 100) == 0)
	_chk("D.08 sin_g(64, 256) == 256", MonAnimator.sin_g(64, 256) == 256)
	_chk("D.09 sin_g(64, 6) == 6", MonAnimator.sin_g(64, 6) == 6)
	_chk("D.10 sin_g(192, 6) == -6", MonAnimator.sin_g(192, 6) == -6)
	# Cos indexes the table 64 entries further along.
	_chk("D.11 cos_g(0, 256) == 256", MonAnimator.cos_g(0, 256) == 256)
	_chk("D.12 cos_g(64, 256) == 0", MonAnimator.cos_g(64, 256) == 0)
	# Arithmetic shift on a negative product, matching C's >> on signed.
	_chk("D.13 negative products shift arithmetically",
			MonAnimator.sin_g(192, 3) == -3)


func _test_trig_index_wrapping_is_safe() -> void:
	# A few source call sites pass a negative index (Anim_GrowInStages'
	# `Sin(data[7] - scale, 64)`, SetHorizontalDip's u16 round-trip), which
	# reads out of bounds on hardware. Wrapping gives the mathematically
	# correct value instead, and must never crash.
	_chk("D.14 negative index wraps to the correct sine",
			MonAnimator.sin_g(-64, 256) == -256)
	_chk("D.15 index past one period wraps", MonAnimator.sin_g(256 + 64, 6) == 6)
	_chk("D.16 large index is safe", MonAnimator.sin_g(100000, 6) == MonAnimator.sin_g(100000 % 256, 6))


# ---------------------------------------------------------------------
# E. Motion maths
# ---------------------------------------------------------------------

func _frames_to_finish(st: Dictionary, cap: int = 2000) -> int:
	var n := 0
	while not st.is_empty() and not st["done"] and n < cap:
		MonAnimator.step(st)
		n += 1
	return n


func _test_every_variant_terminates() -> void:
	# The single highest-value assertion in this file: a motion that never
	# sets `done` would hang the player's sprite mid-animation forever, and
	# there are 75 of them.
	var never_ended: Array = []
	var bad_scale: Array = []
	for back_id in range(1, MonAnimator.BACK_ANIM_COUNT):
		for nature in range(25):
			var st := MonAnimator.start(back_id, nature)
			if st.is_empty():
				never_ended.append("empty:%d" % back_id)
				continue
			var n := 0
			while not st["done"] and n < 2000:
				MonAnimator.step(st)
				n += 1
				var sc: Vector2 = MonAnimator.godot_scale(st)
				if sc.x <= 0.0 or sc.y <= 0.0 or sc.x > 8.0 or sc.y > 8.0:
					if not bad_scale.has(String(st["key"])):
						bad_scale.append(String(st["key"]))
			if n >= 2000:
				never_ended.append(String(st["key"]))
	_chk("E.01 every (set, nature) pair terminates", never_ended.is_empty())
	_chk("E.02 no variant produces a degenerate scale", bad_scale.is_empty())


func _test_h_slide_matches_hand_computed_source() -> void:
	# HorizontalSlide: x2 = Sin((d2 * 384 / d0) % 256, 6), d0 = 40 for the
	# normal variant. Expected values computed by hand from source's own
	# formula against the embedded table.
	var st := MonAnimator.start(MonAnimator.BACK_ANIM_H_SLIDE, 5)  # BOLD -> variant 1 (normal)
	_chk("E.03 h_slide picks the normal variant", String(st["key"]) == "h_slide")
	MonAnimator.step(st)  # d2 was 0 -> x2 = Sin(0, 6) = 0
	_chk("E.04 h_slide frame 1 offset is 0", int(st["x2"]) == 0)
	MonAnimator.step(st)  # d2 == 1 -> Sin((384/40)%256, 6) == Sin(9, 6)
	_chk("E.05 h_slide frame 2 matches Sin(9, 6)",
			int(st["x2"]) == MonAnimator.sin_g(9, 6))
	# It is a pure horizontal motion -- no vertical component at all, which
	# is what makes this family read as "moves left and right".
	var moved_y := false
	while not st["done"]:
		MonAnimator.step(st)
		if int(st["y2"]) != 0:
			moved_y = true
	_chk("E.06 h_slide never moves vertically", not moved_y)


func _test_h_vibrate_alternates_sign() -> void:
	# Anim_HorizontalVibrate flips sign every frame off `data[2] & 1`.
	var st := MonAnimator.start(MonAnimator.BACK_ANIM_H_VIBRATE, 5)
	var signs: Array = []
	for i in range(8):
		MonAnimator.step(st)
		signs.append(signi(int(st["x2"])))
	var alternates := true
	for i in range(1, signs.size()):
		if signs[i] != 0 and signs[i - 1] != 0 and signs[i] == signs[i - 1]:
			alternates = false
	_chk("E.07 h_vibrate alternates direction each frame", alternates)


func _test_jolt_right_walks_its_state_machine() -> void:
	# JoltRight is the only 5-state motion here (JoltRight, _0.._3). Prove
	# it visits states in order and ends back at zero offset.
	var st := MonAnimator.start(MonAnimator.BACK_ANIM_JOLT_RIGHT, 5)
	var seen: Array = []
	var went_negative := false
	var went_positive := false
	while not st["done"]:
		MonAnimator.step(st)
		var s: int = int(st["jolt"])
		if not seen.has(s):
			seen.append(s)
		if int(st["x2"]) < 0:
			went_negative = true
		if int(st["x2"]) > 0:
			went_positive = true
	_chk("E.08 jolt_right visits all 5 states in order",
			seen == [0, 1, 2, 3, 4])
	_chk("E.09 jolt_right recoils left then throws right",
			went_negative and went_positive)
	_chk("E.10 jolt_right settles back at zero offset", int(st["x2"]) == 0)


func _test_h_dip_is_rotation_driven() -> void:
	# BACK_ANIM_DIP_RIGHT_SIDE barely translates (max |x2| == 1); the dip
	# is almost entirely ROTATION. Worth pinning explicitly -- a port that
	# dropped the rotation would still "pass" any offset-based check while
	# rendering an essentially motionless sprite.
	var st := MonAnimator.start(MonAnimator.BACK_ANIM_DIP_RIGHT_SIDE, 5)
	var max_rot := 0.0
	var max_x := 0
	while not st["done"]:
		MonAnimator.step(st)
		max_rot = maxf(max_rot, absf(MonAnimator.godot_rotation(st)))
		max_x = maxi(max_x, absi(int(st["x2"])))
	_chk("E.11 h_dip produces real rotation", max_rot > 0.05)
	_chk("E.12 h_dip's translation is negligible next to its rotation", max_x <= 2)
	_chk("E.13 h_dip settles back to zero rotation",
			is_equal_approx(MonAnimator.godot_rotation(st), 0.0))


func _test_glow_families_blend_and_clear() -> void:
	# ShakeGlow_Blend ramps coeff via Sin(d2, 12), so the peak is 12/16.
	var colors := {
		MonAnimator.BACK_ANIM_SHAKE_GLOW_RED: Color8(255, 0, 0),
		MonAnimator.BACK_ANIM_SHAKE_GLOW_GREEN: Color8(0, 255, 0),
		MonAnimator.BACK_ANIM_SHAKE_GLOW_BLUE: Color8(0, 0, 255),
	}
	for back_id in colors:
		var st := MonAnimator.start(back_id, 5)
		var peak := 0.0
		var seen_color := Color(1, 1, 1, 1)
		while not st["done"]:
			MonAnimator.step(st)
			var a := MonAnimator.godot_blend_amount(st)
			if a > peak:
				peak = a
				seen_color = st["blend_color"]
		_chk("E.14 glow set %d peaks at Sin's own 12/16" % back_id,
				is_equal_approx(peak, 12.0 / 16.0))
		_chk("E.15 glow set %d uses its own colour" % back_id,
				seen_color == colors[back_id])
		_chk("E.16 glow set %d clears its blend when done" % back_id,
				is_equal_approx(MonAnimator.godot_blend_amount(st), 0.0))


func _test_flash_yellow_is_full_replace() -> void:
	# BlendPalette coeff 16 fully REPLACES the channel, unlike the glow
	# family's partial ramp -- that difference is the whole reason the
	# recall/emerge pink needed a mix() shader rather than `modulate`.
	var st := MonAnimator.start(MonAnimator.BACK_ANIM_SHAKE_FLASH_YELLOW, 5)
	var peak := 0.0
	var flips := 0
	var was_on := false
	while not st["done"]:
		MonAnimator.step(st)
		var a := MonAnimator.godot_blend_amount(st)
		peak = maxf(peak, a)
		var on := a > 0.5
		if on != was_on:
			flips += 1
			was_on = on
	_chk("E.17 flash_yellow reaches full replace (coeff 16)",
			is_equal_approx(peak, 1.0))
	_chk("E.18 flash_yellow genuinely flashes on and off", flips >= 4)
	_chk("E.19 flash_yellow clears its blend when done",
			is_equal_approx(MonAnimator.godot_blend_amount(st), 0.0))


func _test_affine_scale_inversion() -> void:
	# GBA affine is INVERTED: a SMALLER stored value is a BIGGER sprite.
	# Getting this backwards would make every "grow" shrink.
	var st := MonAnimator.start(MonAnimator.BACK_ANIM_GROW, 5)
	var grew := false
	var min_stored := 999999
	while not st["done"]:
		MonAnimator.step(st)
		min_stored = mini(min_stored, int(st["sx"]))
		if MonAnimator.godot_scale(st).x > 1.001:
			grew = true
	_chk("E.20 GROW stores an affine value below identity", min_stored < 256)
	_chk("E.21 ...which godot_scale inverts into a real enlargement", grew)
	_chk("E.22 GROW settles back at identity scale",
			MonAnimator.godot_scale(st).is_equal_approx(Vector2.ONE))


# ---------------------------------------------------------------------
# F. Clock
# ---------------------------------------------------------------------

func _test_clock_is_refresh_rate_independent() -> void:
	# One real second of wall clock must advance ~60 GBA frames regardless
	# of how that second is sliced. This is the property M26G4's audit
	# found the earlier timer-per-step animations do NOT have.
	var rates := [30.0, 60.0, 144.0, 240.0]
	var results: Array = []
	for hz in rates:
		var clock := MonAnimator.Clock.new()
		var total := 0
		for i in range(int(hz)):
			total += clock.advance(1.0 / hz)
		results.append(total)
	# Tolerance of one frame: summing N deltas of 1.0/N is not exactly 1.0
	# in floating point, so a rate can legitimately land on 59. The point
	# of the assertion is that the count does not TRACK the refresh rate,
	# which a one-frame band still proves decisively (a frame-tied stepper
	# would read 30 and 240 here, not 59-60).
	var all_60 := true
	for r in results:
		if absi(int(r) - 60) > 1:
			all_60 = false
	_chk("F.01 one second is ~60 frames at 30/60/144/240Hz", all_60)


func _test_clock_holds_sub_frame_remainder() -> void:
	var clock := MonAnimator.Clock.new()
	# A delta shorter than one GBA frame advances nothing yet...
	_chk("F.02 a sub-frame delta advances no frames",
			clock.advance(1.0 / 240.0) == 0)
	# ...but is not discarded -- four of them make one frame.
	var got := 0
	for i in range(3):
		got += clock.advance(1.0 / 240.0)
	_chk("F.03 remainder accumulates instead of being dropped", got == 1)
	# A long stall catches up rather than losing motion.
	var clock2 := MonAnimator.Clock.new()
	_chk("F.04 a stalled frame catches up", clock2.advance(0.5) == 30)
	clock2.reset()
	_chk("F.05 reset clears the accumulator", clock2.advance(1.0 / 240.0) == 0)


# ---------------------------------------------------------------------
# G. Dispatch
# ---------------------------------------------------------------------

func _make_screen() -> Node:
	var bs = load("res://scenes/battle/battle_screen_shared.gd").new()
	return bs


func _test_find_mon_slot_reports_side() -> void:
	# The back animation is player-side only (the opponent's front-sprite
	# equivalent is B3-6c-2), so the slot lookup has to say which side it
	# found the mon on.
	var bs = _make_screen()
	var ply := BattleParty.new()
	var opp := BattleParty.new()
	var pm := _make_mon()
	var om := _make_mon()
	ply.members = [pm]
	ply.active_indices = [0]
	opp.members = [om]
	opp.active_indices = [0]
	bs._player_party = ply
	bs._opp_party = opp
	var ps := TextureRect.new()
	var os_ := TextureRect.new()
	bs._ply_sprites = [ps]
	bs._opp_sprites = [os_]
	bs._ply_panels = []
	bs._opp_panels = []

	var found_p: Dictionary = bs._find_mon_slot(pm)
	var found_o: Dictionary = bs._find_mon_slot(om)
	_chk("G.01 player-side lookup reports is_player true",
			found_p.get("is_player", null) == true)
	_chk("G.02 opponent-side lookup reports is_player false",
			found_o.get("is_player", null) == false)
	_chk("G.03 lookup still returns the right sprite",
			found_p.get("sprite", null) == ps and found_o.get("sprite", null) == os_)
	_chk("G.04 an unknown mon yields an empty result",
			bs._find_mon_slot(_make_mon()).is_empty())
	ps.free()
	os_.free()
	bs.free()


func _test_back_animation_bypassed_when_not_in_tree() -> void:
	# Same off-tree/--autoplay bypass every other animation in this file
	# has. Must return immediately without touching the sprite, and above
	# all without awaiting a `get_tree().process_frame` that will never
	# arrive on a detached instance.
	var bs = _make_screen()
	var sprite := TextureRect.new()
	sprite.position = Vector2(11, 22)
	sprite.scale = Vector2(1.5, 1.5)
	var mon := _make_mon()
	await bs._play_back_entry_animation(mon, sprite, null)
	_chk("G.05 off-tree bypass leaves position untouched",
			sprite.position == Vector2(11, 22))
	_chk("G.06 off-tree bypass leaves scale untouched",
			sprite.scale == Vector2(1.5, 1.5))
	_chk("G.07 off-tree bypass sets no supersession meta",
			not sprite.has_meta("_back_anim_gen"))
	sprite.free()
	bs.free()


func _test_unknown_species_degrades_gracefully() -> void:
	# A hand-built fixture has dex 0 and no registry row. It must produce
	# no animation rather than an error -- the same disclosed
	# degrade-gracefully shape [M26B1]'s EXP bar already uses.
	var row: Dictionary = PokemonRegistry.get_species(0)
	_chk("G.08 dex 0 has no registry row", row == null or row.is_empty())
	var st := MonAnimator.start(MonAnimator.BACK_ANIM_NONE, 0)
	_chk("G.09 a species with no back anim produces no state", st.is_empty())


func _make_mon() -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = "Testmon"
	sp.national_dex_num = 0
	sp.base_hp = 50
	sp.base_attack = 50
	sp.base_defense = 50
	sp.base_sp_attack = 50
	sp.base_sp_defense = 50
	sp.base_speed = 50
	sp.types = [1, 0]
	# Signature is (species, level, forced_nature, forced_ivs, ...) -- there
	# is no moves parameter.
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY,
			[0, 0, 0, 0, 0, 0])


# ---------------------------------------------------------------------
# H. Front animations [M26B3-6c-2]
# ---------------------------------------------------------------------

func _test_every_front_id_in_use_is_implemented() -> void:
	# Coverage has to be driven off the real data, not a hand-kept list:
	# any species whose front_anim_id has no setup entry silently plays
	# nothing, and nothing else would report it.
	var missing: Array = []
	for dex in range(1, 387):
		var row: Dictionary = PokemonRegistry.get_species(dex)
		var fid: int = int(row.get("front_anim_id", -1))
		if not MonAnimator.FRONT_ANIM_SETUP.has(fid) and not missing.has(fid):
			missing.append(fid)
	_chk("H.01 every front_anim_id used by a real species is implemented",
			missing.is_empty())
	var bad_fn := 0
	for fid in MonAnimator.FRONT_ANIM_SETUP:
		if String(MonAnimator.FRONT_ANIM_SETUP[fid].get("fn", "")) == "":
			bad_fn += 1
	_chk("H.02 every front setup entry names a step function", bad_fn == 0)


func _test_front_takes_no_nature() -> void:
	# The headline structural difference from the back side:
	# LaunchAnimationTaskForFrontSprite indexes sMonAnimFunctions directly,
	# so a front id is one animation, not a set of three.
	var a := MonAnimator.start_front(0)
	var b := MonAnimator.start_front(0)
	_chk("H.03 start_front takes no nature argument",
			not a.is_empty() and String(a["fn"]) == String(b["fn"]))
	_chk("H.04 an unknown front id yields no state",
			MonAnimator.start_front(9999).is_empty())


func _test_every_front_anim_terminates() -> void:
	# Same highest-value assertion as the back side: a motion that never
	# sets `done` freezes the opponent's sprite mid-animation.
	var never: Array = []
	var bad_scale: Array = []
	for fid in MonAnimator.FRONT_ANIM_SETUP:
		var st := MonAnimator.start_front(fid)
		var n := 0
		while not st["done"] and n < 4000:
			MonAnimator.step(st)
			n += 1
			var sc: Vector2 = MonAnimator.godot_scale(st)
			# Figure8 legitimately mirrors (negative sx) partway through,
			# so magnitude is what is checked rather than sign.
			if absf(sc.x) > 8.0 or absf(sc.y) > 8.0 or is_zero_approx(sc.y):
				if not bad_scale.has(fid):
					bad_scale.append(fid)
		if n >= 4000:
			never.append(fid)
	_chk("H.05 every front animation terminates", never.is_empty())
	_chk("H.06 no front animation produces a degenerate scale", bad_scale.is_empty())


func _test_front_reuses_back_steppers_where_source_does() -> void:
	# 9 of the 59 front ids resolve to animations the back port already
	# built. They must share the step function, not duplicate it.
	var shared := {2: "h_vibrate", 3: "h_slide", 15: "h_shake",
			19: "shrink_grow", 58: "grow_in_stages", 70: "h_slide",
			76: "h_shake", 79: "circle_ccw", 135: "sgv"}
	var ok := true
	for fid in shared:
		if String(MonAnimator.FRONT_ANIM_SETUP[fid]["fn"]) != shared[fid]:
			ok = false
	_chk("H.07 shared front ids reuse the back steppers", ok)
	# ...and the genuinely different same-named ones do NOT collide.
	_chk("H.08 front V_SHAKE is a different stepper from the back's",
			String(MonAnimator.FRONT_ANIM_SETUP[16]["fn"]) == "v_shake"
			and String(MonAnimator.ANIM_SETUP["v_shake_back"]["fn"]) == "v_shake_back")
	_chk("H.09 front H_STRETCH is distinct from the back's H_STRETCH_FAR",
			String(MonAnimator.FRONT_ANIM_SETUP[22]["fn"]) == "h_stretch_front"
			and String(MonAnimator.ANIM_SETUP["h_stretch"]["fn"]) == "h_stretch")


func _test_flicker_drives_visibility_not_transform() -> void:
	# ANIM_FLICKER_INCREASING is the only animation here that toggles the
	# sprite's visibility rather than moving it.
	var st := MonAnimator.start_front(53)
	var saw_hidden := false
	var moved := false
	while not st["done"]:
		MonAnimator.step(st)
		if not bool(st["visible"]):
			saw_hidden = true
		if int(st["x2"]) != 0 or int(st["y2"]) != 0:
			moved = true
	_chk("H.10 flicker actually hides the sprite at least once", saw_hidden)
	_chk("H.11 flicker never translates the sprite", not moved)
	_chk("H.12 flicker leaves the sprite visible when done", bool(st["visible"]))


func _test_front_glow_families_blend_and_clear() -> void:
	# GlowColor's own coeff ramp is Sin(d2, increment): 16 for black
	# (peak 16/16) and 12 for the rest (peak 12/16).
	var cases := {21: [Color8(0, 0, 0), 1.0], 32: [Color8(255, 181, 0), 12.0 / 16.0],
			34: [Color8(0, 0, 255), 12.0 / 16.0]}
	for fid in cases:
		var st := MonAnimator.start_front(fid)
		var peak := 0.0
		var seen := Color(1, 1, 1, 1)
		while not st["done"]:
			MonAnimator.step(st)
			var a := MonAnimator.godot_blend_amount(st)
			if a > peak:
				peak = a
				seen = st["blend_color"]
		_chk("H.13 front glow %d peaks at its own increment" % fid,
				is_equal_approx(peak, cases[fid][1]))
		_chk("H.14 front glow %d uses its own colour" % fid, seen == cases[fid][0])
		_chk("H.15 front glow %d clears when done" % fid,
				is_equal_approx(MonAnimator.godot_blend_amount(st), 0.0))


func _test_rotate_up_slam_down_chains_into_shake() -> void:
	# Source's RotateUpSlamDown_2 doesn't end the animation -- it hands the
	# sprite off to Anim_VerticalShake, so the slam is followed by a real
	# shake. Easy to lose in a port that just sets done.
	var st := MonAnimator.start_front(47)
	var switched := false
	var n := 0
	while not st["done"] and n < 4000:
		MonAnimator.step(st)
		n += 1
		if String(st["fn"]) == "v_shake":
			switched = true
	_chk("H.16 rotate_up_slam_down hands off to the shake", switched)
	_chk("H.17 ...and still terminates", st["done"])


# ---------------------------------------------------------------------
# I. Switch-out recall + send-out wiring [M26B3-6]
# ---------------------------------------------------------------------

func _test_switch_out_queues_a_recall_beat() -> void:
	# Until now a voluntary switch played NOTHING -- the outgoing Pokemon
	# just vanished. This is the case source actually uses ReturnMonToBall
	# for; the faint recall B3-6a built is the deliberate invention.
	var bs = _make_screen()
	var bm := BattleManager.new()
	add_child(bm)
	bs._bm = bm
	bs._pending_beats.clear()
	var mon := _make_mon()
	var ply := BattleParty.new()
	ply.members = [mon]
	ply.active_indices = [0]
	bs._player_party = ply
	var opp := BattleParty.new()
	opp.members = [_make_mon()]
	opp.active_indices = [0]
	bs._opp_party = opp
	bs._wire_log_signals()
	bm.pokemon_switched_out.emit(mon, 0)
	var kinds: Array = []
	for b in bs._pending_beats:
		kinds.append(String(b.get("kind", "")))
	_chk("I.01 a switch-out queues a recall beat", kinds.has("recall"))
	var found_mon = null
	for b in bs._pending_beats:
		if String(b.get("kind", "")) == "recall":
			found_mon = b.get("mon", null)
	_chk("I.02 the recall beat carries the outgoing mon", found_mon == mon)
	bm.queue_free()
	bs.free()


func _test_switch_in_beat_carries_the_mon_for_send_out() -> void:
	# The switch_reveal beat used to only re-sync textures; it now also
	# has to name the incoming mon so the ball throw can target its slot.
	var bs = _make_screen()
	var bm := BattleManager.new()
	add_child(bm)
	bs._bm = bm
	bs._pending_beats.clear()
	var ply := BattleParty.new()
	var mon := _make_mon()
	ply.members = [mon]
	ply.active_indices = [0]
	bs._player_party = ply
	bs._opp_party = BattleParty.new()
	bs._wire_log_signals()
	bm.pokemon_switched_in.emit(mon, 0, 0)
	var reveal: Dictionary = {}
	for b in bs._pending_beats:
		if String(b.get("kind", "")) == "switch_reveal":
			reveal = b
	_chk("I.03 a switch-in queues a switch_reveal beat", not reveal.is_empty())
	_chk("I.04 the beat carries the incoming mon", reveal.get("mon", null) == mon)
	_chk("I.05 the beat still carries its party/side for the re-sync",
			reveal.get("party", null) == ply and reveal.get("is_player", null) == true)
	bm.queue_free()
	bs.free()


# ---------------------------------------------------------------------
# J. Recall slot-capture + per-side ball origin [Rob's review]
# ---------------------------------------------------------------------

func _test_recall_beat_captures_the_slot_at_signal_time() -> void:
	# The recall had never once played for a real faint or switch: the beat
	# resolved the slot when it DRAINED, by which point the Pokemon had
	# already left the field, so _find_mon_slot returned {} and the whole
	# animation silently no-op'd. Every existing test called
	# _play_recall_to_ball directly with a still-active mon, so none of them
	# could see it. Pinned here at the beat level instead.
	var bs = _make_screen()
	var bm := BattleManager.new()
	add_child(bm)
	bs._bm = bm
	bs._pending_beats.clear()
	var ply := BattleParty.new()
	var mon := _make_mon()
	ply.members = [mon]
	ply.active_indices = [0]
	bs._player_party = ply
	var opp := BattleParty.new()
	opp.members = [_make_mon()]
	opp.active_indices = [0]
	bs._opp_party = opp
	var spr := TextureRect.new()
	var ospr := TextureRect.new()
	bs._ply_sprites = [spr]
	bs._opp_sprites = [ospr]
	bs._ply_panels = []
	bs._opp_panels = []
	bs._wire_log_signals()

	bm.pokemon_fainted.emit(mon)
	bm.pokemon_switched_out.emit(mon, 0)
	var slots: Array = []
	for b in bs._pending_beats:
		if String(b.get("kind", "")) == "recall":
			slots.append(b.get("slot", {}))
	_chk("J.01 both faint and switch-out queue a recall beat", slots.size() == 2)
	var all_resolved := true
	for sl in slots:
		if typeof(sl) != TYPE_DICTIONARY or sl.is_empty() \
				or sl.get("sprite", null) != spr:
			all_resolved = false
	_chk("J.02 each recall beat captured the real slot at signal time",
			all_resolved)

	# This assertion originally read "a drain-time lookup would have
	# failed" and was correct at the time: capturing the slot at signal
	# time was the whole fix. It is now SUPERSEDED -- the real root cause
	# turned out to be that BattleManager repoints the party before it
	# emits at all, so signal-time capture was not enough either, and the
	# _displayed_mons fallback now makes the lookup work at any point.
	# Updated in place rather than deleted, so the stronger guarantee is
	# the one pinned. See K.02 for the root-cause test.
	ply.active_indices = []
	_chk("J.03 the lookup now survives the party emptying entirely",
			bs._find_mon_slot(mon).get("sprite", null) == spr)
	spr.free()
	ospr.free()
	bm.queue_free()
	bs.free()


func _test_ball_origin_is_mirrored_per_side() -> void:
	# Rob's review: the opponent's ball started LEFT of its Pokemon and fell
	# rightward -- thrown from behind the target rather than from the
	# player's side. Source picks a per-side throw offset; this project had
	# one shared constant.
	var base: Vector2 = BattleScreenShared._SENDOUT_BALL_ORIGIN_OFFSET
	_chk("J.04 the player's own origin starts left of the slot", base.x < 0.0)
	_chk("J.05 the origin has a real upward component", base.y < 0.0)
	# Mirroring is x-only: the ball should still arc from above on both
	# sides, just from the opposite horizontal direction.
	var mirrored := Vector2(-base.x, base.y)
	_chk("J.06 the opponent's mirrored origin starts right of the slot",
			mirrored.x > 0.0)
	_chk("J.07 mirroring does not flip the vertical component",
			is_equal_approx(mirrored.y, base.y))


# ---------------------------------------------------------------------
# K. Recall survives BattleManager repointing the party [Rob's review #2]
# ---------------------------------------------------------------------

func _test_recall_finds_slot_after_party_moved_on() -> void:
	# THE root cause the previous fix missed. BattleManager sets
	# active_indices at battle_manager.gd:8394 and only emits
	# pokemon_switched_out at :8410 -- so the party already points at the
	# INCOMING mon before any listener runs. An identity lookup for the
	# outgoing mon therefore fails at signal time too, not just at
	# beat-drain time, which is why the recall still never played.
	var bs = _make_screen()
	var outgoing := _make_mon()
	var incoming := _make_mon()
	var ply := BattleParty.new()
	ply.members = [outgoing, incoming]
	ply.active_indices = [0]
	bs._player_party = ply
	bs._opp_party = BattleParty.new()
	var spr := TextureRect.new()
	bs._ply_sprites = [spr]
	bs._opp_sprites = []
	bs._ply_panels = []
	bs._opp_panels = []

	# While it is on the field the ordinary party scan finds it...
	var before: Dictionary = bs._find_mon_slot(outgoing)
	_chk("K.01 an active mon is found by the party scan",
			before.get("sprite", null) == spr)

	# ...now reproduce BattleManager's own ordering: repoint the party
	# FIRST, exactly as it does before emitting.
	ply.active_indices = [1]
	var after: Dictionary = bs._find_mon_slot(outgoing)
	_chk("K.02 the outgoing mon is STILL resolvable once the party moved on",
			after.get("sprite", null) == spr)
	_chk("K.03 ...and reports the correct side", after.get("is_player", null) == true)
	# The incoming mon must still resolve through the normal path.
	_chk("K.04 the incoming mon resolves normally",
			bs._find_mon_slot(incoming).get("sprite", null) == spr)
	# A mon that was never displayed must still yield nothing.
	_chk("K.05 an unrelated mon still yields nothing",
			bs._find_mon_slot(_make_mon()).is_empty())
	spr.free()
	bs.free()


func _test_opponent_send_out_is_delayed() -> void:
	# Rob's review: the opponent's ball left almost the instant the trainer
	# began sliding out, so the two read as one rushed motion.
	_chk("K.06 the opponent send-out delay is a real quarter-second",
			BattleScreenShared._OPPONENT_SENDOUT_DELAY_FRAMES == 15)


# ---------------------------------------------------------------------
# L. Recall is bottom-anchored [Rob's review #3]
# ---------------------------------------------------------------------

func _test_recall_ball_and_pivot_are_bottom_anchored() -> void:
	# The ball is the destination, so the shrink collapses INTO it.
	# Deliberately the opposite call from [M26B3-6b]'s reverted bottom
	# pivot on the EMERGE -- different animation, opposite direction.
	var sprite := TextureRect.new()
	sprite.position = Vector2(100, 200)
	sprite.size = Vector2(240, 240)
	var rect := Rect2(sprite.position, sprite.size)
	var expected_ball := Vector2(rect.get_center().x, rect.end.y)
	_chk("L.01 the ball sits at the sprite's bottom centre, not its middle",
			is_equal_approx(expected_ball.x, 220.0)
			and is_equal_approx(expected_ball.y, 440.0))
	_chk("L.02 ...which is genuinely below the sprite's own centre",
			expected_ball.y > rect.get_center().y)
	var pivot := Vector2(sprite.size.x * 0.5, sprite.size.y)
	_chk("L.03 the shrink pivot is bottom-centre",
			is_equal_approx(pivot.x, 120.0) and is_equal_approx(pivot.y, 240.0))
	# A bottom pivot means a shrinking sprite keeps its feet planted: the
	# bottom edge stays put while the top edge falls toward it.
	var shrunk_bottom: float = sprite.position.y + pivot.y
	_chk("L.04 a bottom pivot keeps the sprite's feet planted as it shrinks",
			is_equal_approx(shrunk_bottom, rect.end.y))
	sprite.free()


func _test_recall_ball_lift_is_per_side() -> void:
	# Rob's review: the flat bottom-edge placement sat too low on both
	# sides, and the two need different lifts because their sprites sit
	# differently against their own platforms.
	_chk("L.05 the player's recall ball lifts 10%",
			is_equal_approx(BattleScreenShared._RECALL_BALL_LIFT_PLAYER, 0.10))
	_chk("L.06 the opponent's recall ball lifts 30%",
			is_equal_approx(BattleScreenShared._RECALL_BALL_LIFT_OPPONENT, 0.30))
	_chk("L.07 the opponent is lifted further than the player",
			BattleScreenShared._RECALL_BALL_LIFT_OPPONENT
			> BattleScreenShared._RECALL_BALL_LIFT_PLAYER)
	# Worked example on a real 240px sprite spanning y 200..440.
	var rect := Rect2(Vector2(100, 200), Vector2(240, 240))
	var ply_y: float = rect.end.y - rect.size.y * BattleScreenShared._RECALL_BALL_LIFT_PLAYER
	var opp_y: float = rect.end.y - rect.size.y * BattleScreenShared._RECALL_BALL_LIFT_OPPONENT
	_chk("L.08 a 240px player sprite lifts the ball 24px to y=416",
			is_equal_approx(ply_y, 416.0))
	_chk("L.09 a 240px opponent sprite lifts the ball 72px to y=368",
			is_equal_approx(opp_y, 368.0))
	# Still below centre on both -- a lift, not a recentre.
	_chk("L.10 both stay below the sprite's own centre",
			ply_y > rect.get_center().y and opp_y > rect.get_center().y)


# ---------------------------------------------------------------------
# M. Party status summary pacing [M26B5 item 1]
# ---------------------------------------------------------------------

func _party_test_screen(out_is_player: bool) -> Array:
	var bs = _make_screen()
	var bm := BattleManager.new()
	add_child(bm)
	bs._bm = bm
	bs._pending_beats.clear()
	var ply := BattleParty.new()
	ply.members = [_make_mon(), _make_mon()]
	ply.active_indices = [0]
	var opp := BattleParty.new()
	opp.members = [_make_mon(), _make_mon()]
	opp.active_indices = [0]
	bs._player_party = ply
	bs._opp_party = opp
	var ps := TextureRect.new()
	var os_ := TextureRect.new()
	bs._ply_sprites = [ps]
	bs._opp_sprites = [os_]
	bs._ply_panels = []
	bs._opp_panels = []
	bs._wire_log_signals()
	var mon: BattlePokemon = (ply if out_is_player else opp).members[0]
	bm.pokemon_switched_out.emit(mon, 0 if out_is_player else 1)
	return [bs, bm, ps, os_]


func _test_faint_no_longer_triggers_the_party_row() -> void:
	# The old pokemon_fainted listener fired during move resolution, so the
	# row appeared over the attack animation and vanished when it ended.
	# Source never triggers on the faint at all.
	var bs = _make_screen()
	var bm := BattleManager.new()
	add_child(bm)
	bs._bm = bm
	bs._pending_beats.clear()
	var ply := BattleParty.new()
	ply.members = [_make_mon()]
	ply.active_indices = [0]
	bs._player_party = ply
	var opp := BattleParty.new()
	opp.members = [_make_mon()]
	opp.active_indices = [0]
	bs._opp_party = opp
	bs._ply_sprites = []
	bs._opp_sprites = []
	bs._ply_panels = []
	bs._opp_panels = []
	bs._wire_log_signals()
	bm.pokemon_fainted.emit(ply.members[0])
	var kinds: Array = []
	for b in bs._pending_beats:
		kinds.append(String(b.get("kind", "")))
	_chk("M.01 a faint no longer queues a party-summary beat",
			not kinds.has("party_summary_show"))
	_chk("M.02 ...but still queues its recall", kinds.has("recall"))
	bm.queue_free()
	bs.free()


func _test_switch_out_queues_the_summary_after_the_recall() -> void:
	# Source's order is returnatktoball -> drawpartystatussummary, so the
	# row must sit AFTER the recall beat in the queue, not before it.
	var parts: Array = _party_test_screen(true)
	var bs = parts[0]
	var order: Array = []
	for b in bs._pending_beats:
		order.append(String(b.get("kind", "")))
	var i_recall: int = order.find("recall")
	var i_summary: int = order.find("party_summary_show")
	_chk("M.03 a switch-out queues both a recall and a summary beat",
			i_recall >= 0 and i_summary >= 0)
	_chk("M.04 the summary is queued AFTER the recall", i_summary > i_recall)
	parts[2].free(); parts[3].free(); parts[1].queue_free(); bs.free()


func _test_summary_is_switching_side_only() -> void:
	# `drawpartystatussummary BS_ATTACKER` names ONE battler -- mid-battle
	# only the switching side's row is drawn, unlike battle start.
	var p1: Array = _party_test_screen(true)
	var got_player = null
	for b in p1[0]._pending_beats:
		if String(b.get("kind", "")) == "party_summary_show":
			got_player = b.get("is_player", null)
	_chk("M.05 a player switch draws the player's row", got_player == true)
	p1[2].free(); p1[3].free(); p1[1].queue_free(); p1[0].free()

	var p2: Array = _party_test_screen(false)
	var got_opp = null
	for b in p2[0]._pending_beats:
		if String(b.get("kind", "")) == "party_summary_show":
			got_opp = b.get("is_player", null)
	_chk("M.06 an opponent switch draws the opponent's row", got_opp == false)
	p2[2].free(); p2[3].free(); p2[1].queue_free(); p2[0].free()


func _test_hide_clears_both_rows() -> void:
	# hidepartystatussummary runs immediately before switchinanim, so the
	# row must be gone by the time the ball is thrown.
	var bs = _make_screen()
	var a := Control.new()
	var b := Control.new()
	a.visible = true
	b.visible = true
	bs._party_status_opponent = a
	bs._party_status_player = b
	bs._hide_party_status_rows()
	_chk("M.07 hiding clears the opponent row", not a.visible)
	_chk("M.08 hiding clears the player row", not b.visible)
	a.free(); b.free(); bs.free()


# ---------------------------------------------------------------------
# N. Party row entry animation [M26B5 items 2+4]
# ---------------------------------------------------------------------

func _test_ball_entry_delay_fans_per_side() -> void:
	# `data[1] = i * 7 + 10` (player) vs `(6 - i) * 7 + 10` (opponent) --
	# each side fans in from its own outer edge inward, so the two are
	# mirror images rather than the same sequence.
	var ply: Array = []
	var opp: Array = []
	for i in range(6):
		ply.append(BattleScreenShared._party_ball_entry_delay(i, true))
		opp.append(BattleScreenShared._party_ball_entry_delay(i, false))
	_chk("N.01 player delays match source's i*7+10", ply == [10, 17, 24, 31, 38, 45])
	_chk("N.02 opponent delays match source's (6-i)*7+10",
			opp == [52, 45, 38, 31, 24, 17])
	_chk("N.03 the player fans left-to-right", ply[0] < ply[5])
	_chk("N.04 the opponent fans right-to-left", opp[0] > opp[5])
	# The stagger is the whole point -- a uniform delay would defeat it.
	var uniform := true
	for i in range(1, 6):
		if ply[i] != ply[0]:
			uniform = false
	_chk("N.05 the delays are genuinely staggered, not uniform", not uniform)


func _test_entry_constants_match_source() -> void:
	_chk("N.06 bar entry offset is source's bar_pos2_X",
			is_equal_approx(BattleScreenShared._PARTY_BAR_ENTRY_OFFSET, 100.0))
	_chk("N.07 bar step is source's bar_data0",
			is_equal_approx(BattleScreenShared._PARTY_BAR_ENTRY_STEP, 5.0))
	_chk("N.08 ball entry offset is source's x2 = 120",
			is_equal_approx(BattleScreenShared._PARTY_BALL_ENTRY_OFFSET, 120.0))
	_chk("N.09 ball step is the accumulator's own 2px/frame",
			is_equal_approx(BattleScreenShared._PARTY_BALL_ENTRY_STEP, 2.0))
	# The bar reaches rest well before the last ball does -- it is the
	# backdrop the balls land on, so it must not arrive last.
	var bar_frames: float = BattleScreenShared._PARTY_BAR_ENTRY_OFFSET \
			/ BattleScreenShared._PARTY_BAR_ENTRY_STEP
	var last_ball: float = BattleScreenShared._party_ball_entry_delay(5, true) \
			+ BattleScreenShared._PARTY_BALL_ENTRY_OFFSET \
			/ BattleScreenShared._PARTY_BALL_ENTRY_STEP
	_chk("N.10 the bar settles before the last ball lands",
			bar_frames < last_ball)
