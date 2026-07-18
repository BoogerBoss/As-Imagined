extends Node

# M18.5h-2 test suite — IV system (real independent 0-31 per stat, rolled once
# per instance). Second of two sequential M18.5h sub-tiers ([M18.5h-1] Nature
# is complete). EV gain remains explicitly out of scope for all of M18.5h
# (deferred to land with M20) — not touched here.
#
# Ground truth: pokeemerald_expansion
#   IV range:            MAX_PER_STAT_IVS=31 (include/constants/pokemon.h L227)
#   Combined formula:    CalculateMonStats (pokemon.c L1406-1425) — non-HP:
#                         n = (((2*base+iv+ev/4)*level)/100)+5, THEN nature.
#                         HP: n = 2*base+iv; maxHP = ((n+ev/4)*level/100)+level+10.
#                         Re-verified directly this tier — ALREADY byte-for-byte
#                         correct in this project's existing _stat_formula/
#                         _hp_formula since Milestone 1; zero formula changes
#                         needed, only from_species's IV-generation path.
#   IV independence:     source's real IVs come from a separate random "IV
#                         word" (three 5-bit fields per 16-bit half), NOT
#                         personality-derived like gender/nature — this project
#                         reproduces the resulting per-stat 0-31 uniform
#                         DISTRIBUTION via 6 independent randi()%32 calls
#                         rather than modeling an "IV word" concept.
#
# Sections: A (IV range validity), B (independence across the 6 stats —
# statistical, guards against "one shared roll for all 6" bug), C (non-HP
# stat-formula application at IV=0 vs IV=31), D (HP's own distinct formula at
# IV=0 vs IV=31), E (forced_ivs full-array determinism — the M24-readiness
# requirement), F (forced_ivs PARTIAL per-stat forcing — some stats forced,
# others still roll normally, per M24's real "some stats maxed, rest whatever"
# need).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_a_iv_range_validity()
	_test_section_b_independence()
	_test_section_c_stat_formula_application()
	_test_section_d_hp_formula_application()
	_test_section_e_forced_ivs_full_determinism()
	_test_section_f_forced_ivs_partial_forcing()

	var total := _pass + _fail
	print("m18_5h2_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# Round base stats (100 everywhere) chosen specifically so the formula lands on
# clean, hand-verifiable numbers, matching [M18.5h-1]'s own fixture shape.
# Level 50, EV=0 always (from_species always zeros EVs — EV gain is out of
# scope for all of M18.5h).
#   Non-HP, IV=0:  floori((2*100+0+0)*50/100.0)+5   = 105
#   Non-HP, IV=31: floori((2*100+31+0)*50/100.0)+5  = floori(115.5)+5 = 120
#   HP, IV=0:      floori((2*100+0+0)*50/100.0)+60  = 160
#   HP, IV=31:     floori((2*100+31+0)*50/100.0)+60 = 175
func _make_species() -> PokemonSpecies:
	var sp := PokemonSpecies.new()
	sp.species_name = "IVTestMon"
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = 100
	sp.base_attack = 100
	sp.base_defense = 100
	sp.base_sp_attack = 100
	sp.base_sp_defense = 100
	sp.base_speed = 100
	return sp


# ── Section A: IV range validity ────────────────────────────────────────────

func _test_section_a_iv_range_validity() -> void:
	var n := 3000
	var out_of_range := 0
	for _i in range(n):
		var ivs: Array[int] = BattlePokemon._roll_ivs()
		for v in ivs:
			if v < 0 or v > 31:
				out_of_range += 1
	_chk("A01 every rolled IV across %d instances (6 stats each) falls in [0, 31]" % n,
			out_of_range == 0)

	# Discriminator: confirm the roll actually reaches both extremes (0 and 31)
	# somewhere across this many samples — proves the range isn't accidentally
	# narrower than claimed (e.g. randi() % 31 instead of % 32).
	var saw_zero := false
	var saw_31 := false
	for _i in range(n):
		var ivs: Array[int] = BattlePokemon._roll_ivs()
		for v in ivs:
			if v == 0:
				saw_zero = true
			if v == 31:
				saw_31 = true
	_chk("A02 discriminator: 0 is actually reachable across %d instances" % n, saw_zero)
	_chk("A03 discriminator: 31 is actually reachable across %d instances" % n, saw_31)


# ── Section B: independence across the 6 stats (not one shared roll) ───────────

func _test_section_b_independence() -> void:
	var n := 3000

	# B1: each of the 6 stat SLOTS individually shows a roughly uniform 0-31
	# distribution (expected ~n/32 per bucket per slot).
	var counts: Array = []
	for _s in range(6):
		var bucket: Array[int] = []
		bucket.resize(32)
		for i in range(32):
			bucket[i] = 0
		counts.append(bucket)
	var same_01 := 0  # how often stat[0] == stat[1] (independence discriminator)
	for _i in range(n):
		var ivs: Array[int] = BattlePokemon._roll_ivs()
		for s in range(6):
			counts[s][ivs[s]] += 1
		if ivs[0] == ivs[1]:
			same_01 += 1

	var expected: float = float(n) / 32.0
	var low: float = expected * 0.4
	var high: float = expected * 1.8
	var all_slots_uniform := true
	for s in range(6):
		var slot_counts: Array = counts[s]
		for i in range(32):
			if slot_counts[i] < low or slot_counts[i] > high:
				all_slots_uniform = false
	_chk("B01 all 6 stat slots individually show a roughly uniform 0-31 " +
			"distribution (n=%d per slot, expected ~%.1f per bucket)" % [n, expected],
			all_slots_uniform)

	# B2: the KEY independence discriminator. If stats[0] and stats[1] were
	# secretly the SAME roll (a "one shared roll for all 6" bug), same_01 would
	# be ~100% (n). If independent, P(equal) = 1/32 ≈ 3.1%. Wide band around
	# the independent-case expectation, nowhere near the shared-roll case.
	var same_rate: float = float(same_01) / n
	_chk("B02 independence: stat[0]==stat[1] only ~1/32 of the time " +
			"(observed=%.3f, n=%d) -- NOT a shared roll applied to all 6 stats" %
			[same_rate, n], same_rate < 0.12)


# ── Section C: non-HP stat-formula application (IV=0 vs IV=31) ─────────────────

func _test_section_c_stat_formula_application() -> void:
	# Nature forced to HARDY (neutral) throughout this section, isolating the
	# IV term's own effect from [M18.5h-1]'s multiplier.
	var sp0 := _make_species()
	var forced_zero: Array = [0, 0, 0, 0, 0, 0]
	var c0 := BattlePokemon.from_species(sp0, 50, BattlePokemon.NATURE_HARDY, forced_zero)
	_chk("C1.01 IV=0: Attack == 105 (pre-existing pre-IV-system baseline)", c0.attack == 105)
	_chk("C1.02 IV=0: Defense == 105", c0.defense == 105)
	_chk("C1.03 IV=0: Sp.Atk == 105", c0.sp_attack == 105)
	_chk("C1.04 IV=0: Sp.Def == 105", c0.sp_defense == 105)
	_chk("C1.05 IV=0: Speed == 105", c0.speed == 105)

	var sp31 := _make_species()
	var forced_31: Array = [31, 31, 31, 31, 31, 31]
	var c31 := BattlePokemon.from_species(sp31, 50, BattlePokemon.NATURE_HARDY, forced_31)
	_chk("C2.01 IV=31: Attack == 120 (floor((2*100+31)*50/100)+5)", c31.attack == 120)
	_chk("C2.02 IV=31: Defense == 120", c31.defense == 120)
	_chk("C2.03 IV=31: Sp.Atk == 120", c31.sp_attack == 120)
	_chk("C2.04 IV=31: Sp.Def == 120", c31.sp_defense == 120)
	_chk("C2.05 IV=31: Speed == 120", c31.speed == 120)

	_chk("C3 exact delta IV=0->IV=31 is +15 for every non-HP stat, matching " +
			"source's formula exactly", c31.attack - c0.attack == 15
			and c31.defense - c0.defense == 15 and c31.sp_attack - c0.sp_attack == 15
			and c31.sp_defense - c0.sp_defense == 15 and c31.speed - c0.speed == 15)


# ── Section D: HP's own distinct formula (IV=0 vs IV=31) ───────────────────────

func _test_section_d_hp_formula_application() -> void:
	var sp0 := _make_species()
	var forced_zero: Array = [0, 0, 0, 0, 0, 0]
	var d0 := BattlePokemon.from_species(sp0, 50, BattlePokemon.NATURE_HARDY, forced_zero)
	_chk("D1 HP IV=0: max_hp == 160 (floor((2*100+0)*50/100)+50+10)", d0.max_hp == 160)

	var sp31 := _make_species()
	var forced_31: Array = [31, 31, 31, 31, 31, 31]
	var d31 := BattlePokemon.from_species(sp31, 50, BattlePokemon.NATURE_HARDY, forced_31)
	_chk("D2 HP IV=31: max_hp == 175 (floor((2*100+31)*50/100)+50+10)", d31.max_hp == 175)

	_chk("D3 HP's own exact delta IV=0->IV=31 is +15, matching its distinct " +
			"(different additive constant, no Nature term) formula",
			d31.max_hp - d0.max_hp == 15)


# ── Section E: forced_ivs full-array determinism (M24-readiness) ───────────────

func _test_section_e_forced_ivs_full_determinism() -> void:
	var n := 50
	var target: Array = [12, 31, 0, 20, 5, 31]

	var all_match := true
	for _i in range(n):
		var sp := _make_species()
		var mon := BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, target)
		if mon.ivs != target:
			all_match = false
	_chk("E01 forced_ivs full 6-element array: all %d calls produced exactly " % n +
			"the requested IVs, zero variance", all_match)

	# Discriminator: an UNFORCED call sees >= 2 distinct ivs[STAT_ATK] values
	# across the same n, proving E01 isn't hitting a coincidentally-fixed default.
	var seen: Dictionary = {}
	for _i in range(n):
		var sp := _make_species()
		var mon := BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY)
		seen[mon.ivs[BattlePokemon.STAT_ATK]] = true
	_chk("E02 discriminator: an UNFORCED from_species call sees >= 2 distinct " +
			"Attack IVs across %d calls" % n, seen.size() >= 2)


# ── Section F: forced_ivs PARTIAL per-stat forcing ──────────────────────────────

func _test_section_f_forced_ivs_partial_forcing() -> void:
	var n := 50
	# Force only STAT_HP (=31) and STAT_SPEED (=0); leave the other 4 null (roll
	# normally) -- matches M24's real "some stats maxed, rest whatever" need.
	var partial: Array = [31, null, null, null, null, 0]

	var hp_always_31 := true
	var speed_always_0 := true
	var atk_values: Dictionary = {}
	var def_values: Dictionary = {}
	for _i in range(n):
		var sp := _make_species()
		var mon := BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, partial)
		if mon.ivs[BattlePokemon.STAT_HP] != 31:
			hp_always_31 = false
		if mon.ivs[BattlePokemon.STAT_SPEED] != 0:
			speed_always_0 = false
		atk_values[mon.ivs[BattlePokemon.STAT_ATK]] = true
		def_values[mon.ivs[BattlePokemon.STAT_DEF]] = true

	_chk("F01 partial forcing: the FORCED HP slot (31) stays fixed across " +
			"%d calls, zero variance" % n, hp_always_31)
	_chk("F02 partial forcing: the FORCED Speed slot (0) stays fixed across " +
			"%d calls, zero variance" % n, speed_always_0)
	_chk("F03 partial forcing: the UNFORCED Attack slot still shows >= 2 " +
			"distinct values across %d calls (genuinely still randomized)" % n,
			atk_values.size() >= 2)
	_chk("F04 partial forcing: the UNFORCED Defense slot still shows >= 2 " +
			"distinct values across %d calls (genuinely still randomized)" % n,
			def_values.size() >= 2)

	# Discriminator: the forced values actually land at the requested numbers,
	# not just "some" fixed number -- confirms 31/0 specifically, not a bug
	# that coincidentally pins a DIFFERENT constant every call.
	var sp := _make_species()
	var mon := BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, partial)
	_chk("F05 discriminator: forced HP slot is exactly 31, not some other fixed value",
			mon.ivs[BattlePokemon.STAT_HP] == 31)
	_chk("F06 discriminator: forced Speed slot is exactly 0, not some other fixed value",
			mon.ivs[BattlePokemon.STAT_SPEED] == 0)
