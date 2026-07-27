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
