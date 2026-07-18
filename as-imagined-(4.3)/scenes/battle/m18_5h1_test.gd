extends Node

# M18.5h-1 test suite — Nature system (25 natures, ±10%/-10% on two stats, 5
# neutral). Likes/dislikes flavor-preference data explicitly EXCLUDED per Rob's
# scope decision on docs/m18_5h_recon.md Section B4 — no test coverage for it.
# EV gain is explicitly out of scope for all of M18.5h (deferred to land with
# M20) — not touched here either.
#
# Ground truth: pokeemerald_expansion
#   Nature table:        include/constants/pokemon.h L52-76 (NATURE_HARDY..
#                         NATURE_QUIRKY), cross-checked against gNaturesInfo[]
#                         (pokemon.c L154-453) for 2 samples in the recon,
#                         re-verified directly again at this tier's own Step 0.
#   Stat-formula insert: ModifyStatByNature (pokemon.c L4942-4952), called from
#                         CalculateMonStats (L1408) AFTER the base formula's
#                         own +5 term. floor(stat*110/100) / floor(stat*90/100).
#   HP exemption:         statIndex <= STAT_HP guard + HP computed entirely
#                         outside the loop that calls ModifyStatByNature.
#   Nature assignment:    GetNature/GetNatureFromPersonality (pokemon.c
#                         L4185-4193) — personality % NUM_NATURES(25).
#
# Sections: A (table data-integrity via _nature_stat_pair), B (roll statistical
# distribution, no override), C (stat-formula application: boosted/reduced/
# neutral), D (HP unaffected by any nature), E (forced_nature determinism —
# the M24-readiness requirement, the opposite case from B).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_a_table_data_integrity()
	_test_section_b_roll_distribution()
	_test_section_c_stat_formula_application()
	_test_section_d_hp_unaffected()
	_test_section_e_forced_nature_determinism()

	var total := _pass + _fail
	print("m18_5h1_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# Round base stats (100 everywhere) chosen specifically so the pre-Nature formula
# lands on a clean, hand-verifiable number: floori((2*100+0+0)*50/100.0)+5 = 105
# for every non-HP stat (level 50, IV=0/EV=0 — from_species always zeros both).
# HP: floori((2*100+0+0)*50/100.0)+50+10 = 160.
func _make_species() -> PokemonSpecies:
	var sp := PokemonSpecies.new()
	sp.species_name = "NatureTestMon"
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = 100
	sp.base_attack = 100
	sp.base_defense = 100
	sp.base_sp_attack = 100
	sp.base_sp_defense = 100
	sp.base_speed = 100
	return sp


# ── Section A: 25-nature table data integrity (_nature_stat_pair) ──────────────

func _test_section_a_table_data_integrity() -> void:
	_chk("A01 NUM_NATURES == 25", BattlePokemon.NUM_NATURES == 25)
	_chk("A02 NATURE_HARDY == 0 (first ordinal)", BattlePokemon.NATURE_HARDY == 0)
	_chk("A03 NATURE_QUIRKY == 24 (last ordinal)", BattlePokemon.NATURE_QUIRKY == 24)
	_chk("A04 NATURE_ADAMANT == 3", BattlePokemon.NATURE_ADAMANT == 3)
	_chk("A05 NATURE_TIMID == 10", BattlePokemon.NATURE_TIMID == 10)
	_chk("A06 NATURE_MODEST == 15", BattlePokemon.NATURE_MODEST == 15)

	# Representative sample covering every stat as both a raise AND a lower
	# target at least once across the 5x5 grid.
	var stat_atk := BattlePokemon.STAT_ATK
	var stat_def := BattlePokemon.STAT_DEF
	var stat_spatk := BattlePokemon.STAT_SPATK
	var stat_spdef := BattlePokemon.STAT_SPDEF
	var stat_speed := BattlePokemon.STAT_SPEED

	var adamant := BattlePokemon._nature_stat_pair(BattlePokemon.NATURE_ADAMANT)
	_chk("A07 Adamant: +Atk -SpAtk", adamant == [stat_atk, stat_spatk])
	var naughty := BattlePokemon._nature_stat_pair(BattlePokemon.NATURE_NAUGHTY)
	_chk("A08 Naughty: +Atk -SpDef", naughty == [stat_atk, stat_spdef])
	var bold := BattlePokemon._nature_stat_pair(BattlePokemon.NATURE_BOLD)
	_chk("A09 Bold: +Def -Atk", bold == [stat_def, stat_atk])
	var relaxed := BattlePokemon._nature_stat_pair(BattlePokemon.NATURE_RELAXED)
	_chk("A10 Relaxed: +Def -Speed", relaxed == [stat_def, stat_speed])
	var timid := BattlePokemon._nature_stat_pair(BattlePokemon.NATURE_TIMID)
	_chk("A11 Timid: +Speed -Atk", timid == [stat_speed, stat_atk])
	var modest := BattlePokemon._nature_stat_pair(BattlePokemon.NATURE_MODEST)
	_chk("A12 Modest: +SpAtk -Atk", modest == [stat_spatk, stat_atk])
	var rash := BattlePokemon._nature_stat_pair(BattlePokemon.NATURE_RASH)
	_chk("A13 Rash: +SpAtk -SpDef", rash == [stat_spatk, stat_spdef])
	var calm := BattlePokemon._nature_stat_pair(BattlePokemon.NATURE_CALM)
	_chk("A14 Calm: +SpDef -Atk", calm == [stat_spdef, stat_atk])
	var careful := BattlePokemon._nature_stat_pair(BattlePokemon.NATURE_CAREFUL)
	_chk("A15 Careful: +SpDef -SpAtk", careful == [stat_spdef, stat_spatk])

	# All 5 neutral natures — confirmed [-1, -1] (no raise/lower stat).
	_chk("A16 Hardy is neutral ([-1,-1])",
			BattlePokemon._nature_stat_pair(BattlePokemon.NATURE_HARDY) == [-1, -1])
	_chk("A17 Docile is neutral ([-1,-1])",
			BattlePokemon._nature_stat_pair(BattlePokemon.NATURE_DOCILE) == [-1, -1])
	_chk("A18 Serious is neutral ([-1,-1])",
			BattlePokemon._nature_stat_pair(BattlePokemon.NATURE_SERIOUS) == [-1, -1])
	_chk("A19 Bashful is neutral ([-1,-1])",
			BattlePokemon._nature_stat_pair(BattlePokemon.NATURE_BASHFUL) == [-1, -1])
	_chk("A20 Quirky is neutral ([-1,-1])",
			BattlePokemon._nature_stat_pair(BattlePokemon.NATURE_QUIRKY) == [-1, -1])


# ── Section B: roll statistical distribution (no override — uniform 1/25) ──────

func _test_section_b_roll_distribution() -> void:
	var n := 5000
	var counts: Array[int] = []
	counts.resize(BattlePokemon.NUM_NATURES)
	for i in range(BattlePokemon.NUM_NATURES):
		counts[i] = 0
	var out_of_range := 0
	for _i in range(n):
		var rolled: int = BattlePokemon._roll_nature()
		if rolled < 0 or rolled >= BattlePokemon.NUM_NATURES:
			out_of_range += 1
		else:
			counts[rolled] += 1
	_chk("B01 every roll lands in [0, 24]", out_of_range == 0)

	# Expected ~200 per bucket (n=5000 / 25). Wide tolerance band matching this
	# project's established statistical-sample convention ([M17n-5]/[M18e]/
	# [M18.5d]) — 0.5x to 1.6x expected, generous enough to avoid rerun flakes
	# across 25 simultaneous buckets while still catching a badly-skewed roll.
	var expected: float = float(n) / BattlePokemon.NUM_NATURES
	var low: float = expected * 0.5
	var high: float = expected * 1.6
	var all_in_band := true
	for i in range(BattlePokemon.NUM_NATURES):
		if counts[i] < low or counts[i] > high:
			all_in_band = false
	_chk("B02 all 25 buckets land within [%.0f, %.0f] of expected %.0f (n=%d)" %
			[low, high, expected, n], all_in_band)


# ── Section C: stat-formula application (boosted / reduced / neutral) ──────────

func _test_section_c_stat_formula_application() -> void:
	# C1: Adamant (+Atk -SpAtk). Pre-nature formula = 105 for every non-HP stat.
	var sp1 := _make_species()
	var c1 := BattlePokemon.from_species(sp1, 50, BattlePokemon.NATURE_ADAMANT, [0, 0, 0, 0, 0, 0])
	_chk("C1.01 Adamant: Attack boosted 105 -> 115 (floor(105*1.10))", c1.attack == 115)
	_chk("C1.02 Adamant: Sp.Atk reduced 105 -> 94 (floor(105*0.90))", c1.sp_attack == 94)
	_chk("C1.03 Adamant: Defense untouched (105)", c1.defense == 105)
	_chk("C1.04 Adamant: Sp.Def untouched (105)", c1.sp_defense == 105)
	_chk("C1.05 Adamant: Speed untouched (105)", c1.speed == 105)

	# C2: Timid (+Speed -Atk) — a second boost/reduce pair, different stats.
	var sp2 := _make_species()
	var c2 := BattlePokemon.from_species(sp2, 50, BattlePokemon.NATURE_TIMID, [0, 0, 0, 0, 0, 0])
	_chk("C2.01 Timid: Speed boosted 105 -> 115", c2.speed == 115)
	_chk("C2.02 Timid: Attack reduced 105 -> 94", c2.attack == 94)
	_chk("C2.03 Timid: Defense untouched (105)", c2.defense == 105)
	_chk("C2.04 Timid: Sp.Atk untouched (105)", c2.sp_attack == 105)
	_chk("C2.05 Timid: Sp.Def untouched (105)", c2.sp_defense == 105)

	# C3: Hardy (neutral) — every non-HP stat must be IDENTICAL to the raw
	# pre-Nature formula output (105), not just close.
	var sp3 := _make_species()
	var c3 := BattlePokemon.from_species(sp3, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])
	_chk("C3.01 Hardy (neutral): Attack bit-identical to pre-Nature formula (105)",
			c3.attack == 105)
	_chk("C3.02 Hardy (neutral): Defense bit-identical to pre-Nature formula (105)",
			c3.defense == 105)
	_chk("C3.03 Hardy (neutral): Sp.Atk bit-identical to pre-Nature formula (105)",
			c3.sp_attack == 105)
	_chk("C3.04 Hardy (neutral): Sp.Def bit-identical to pre-Nature formula (105)",
			c3.sp_defense == 105)
	_chk("C3.05 Hardy (neutral): Speed bit-identical to pre-Nature formula (105)",
			c3.speed == 105)


# ── Section D: HP unaffected by nature, regardless of which nature ─────────────

func _test_section_d_hp_unaffected() -> void:
	var expected_hp := 160  # floori((2*100+0+0)*50/100.0) + 50 + 10

	var sp_adamant := _make_species()
	var d1 := BattlePokemon.from_species(sp_adamant, 50, BattlePokemon.NATURE_ADAMANT, [0, 0, 0, 0, 0, 0])
	_chk("D01 Adamant (+Atk -SpAtk): HP unaffected (160)", d1.max_hp == expected_hp)

	var sp_timid := _make_species()
	var d2 := BattlePokemon.from_species(sp_timid, 50, BattlePokemon.NATURE_TIMID, [0, 0, 0, 0, 0, 0])
	_chk("D02 Timid (+Speed -Atk): HP unaffected (160)", d2.max_hp == expected_hp)

	var sp_calm := _make_species()
	var d3 := BattlePokemon.from_species(sp_calm, 50, BattlePokemon.NATURE_CALM, [0, 0, 0, 0, 0, 0])
	_chk("D03 Calm (+SpDef -Atk): HP unaffected (160)", d3.max_hp == expected_hp)

	var sp_hardy := _make_species()
	var d4 := BattlePokemon.from_species(sp_hardy, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])
	_chk("D04 Hardy (neutral): HP unaffected (160)", d4.max_hp == expected_hp)

	# Discriminator: all 4 HP values are pairwise identical, not just each
	# individually matching 160 by coincidence.
	_chk("D05 discriminator: all 4 natures above produce the exact same max_hp",
			d1.max_hp == d2.max_hp and d2.max_hp == d3.max_hp and d3.max_hp == d4.max_hp)


# ── Section E: forced_nature determinism (the M24-readiness requirement) ───────

func _test_section_e_forced_nature_determinism() -> void:
	var n := 50

	# E1: forced_nature=Adamant, n repeated calls, ALL must be exactly Adamant —
	# zero variance, unlike Section B's no-override statistical case.
	var all_adamant := true
	for _i in range(n):
		var sp := _make_species()
		var mon := BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_ADAMANT)
		if mon.nature != BattlePokemon.NATURE_ADAMANT:
			all_adamant = false
	_chk("E01 forced_nature=Adamant: all %d calls produced exactly Adamant, zero variance" % n,
			all_adamant)

	# E2: forced_nature=Timid, a DIFFERENT nature — discriminator confirming E1
	# isn't just always returning a hardcoded default regardless of the argument.
	var all_timid := true
	for _i in range(n):
		var sp := _make_species()
		var mon := BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_TIMID)
		if mon.nature != BattlePokemon.NATURE_TIMID:
			all_timid = false
	_chk("E02 forced_nature=Timid: all %d calls produced exactly Timid, zero variance" % n,
			all_timid)

	# E3: forced_nature=Hardy (ordinal 0) — a genuine edge case. NATURE_HARDY==0
	# could be silently mistaken for "no override" if the forcing check used a
	# falsy test (`if forced_nature:`) instead of an explicit null check
	# (`if forced_nature != null:`); this pins that specific correctness trap.
	var all_hardy := true
	for _i in range(n):
		var sp := _make_species()
		var mon := BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY)
		if mon.nature != BattlePokemon.NATURE_HARDY:
			all_hardy = false
	_chk("E03 forced_nature=Hardy(0): honored as a real override, not mistaken for " +
			"'no override given' (0 vs null pitfall)", all_hardy)

	# E4: discriminator — a plain from_species call (no forced_nature) is NOT
	# pinned to any single nature; sampling n calls should see at least 2
	# distinct values, proving E1-E3 are genuinely testing the override path,
	# not a coincidentally-narrow default.
	var seen: Dictionary = {}
	for _i in range(n):
		var sp := _make_species()
		var mon := BattlePokemon.from_species(sp, 50)
		seen[mon.nature] = true
	_chk("E04 discriminator: an UNFORCED from_species call sees >= 2 distinct " +
			"natures across %d calls (proves B/E aren't both hitting a hardcoded path)" % n,
			seen.size() >= 2)
