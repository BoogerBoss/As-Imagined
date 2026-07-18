extends Node

# M18.5d test suite — Gender infrastructure (data model + instance generation)
#
# This is a data-infrastructure tier, not a battle mechanic — no ability/item
# logic reads gender anywhere yet (confirmed via grep at Step 0; zero hits
# outside pokemon_species.gd's own field declaration). Two layers tested:
#
# Section A: data-integrity — PokemonRegistry.get_species(dex)["gender_ratio"]
#   (the actual live data path this project uses; PokemonSpecies.gender_ratio
#   itself is never populated from real data anywhere in production — no
#   JSON-dict-to-PokemonSpecies-Resource converter exists in this project at
#   all, confirmed at Step 0. Every _make_mon-style test fixture across the
#   whole codebase hand-constructs PokemonSpecies directly instead.) — 5
#   categories, each cross-checked directly against
#   reference/pokeemerald_expansion/src/data/pokemon/species_info/gen_1_families.h,
#   not just internal JSON self-consistency.
#
# Section B: instance-generation — BattlePokemon._roll_gender (exercised via
# from_species, per this tier's own testing plan) — zero-variance checks for
# the three gender-locked categories (no roll happens at all for these) and
# statistical-rate checks (n=2000, wide margins matching [M17n-5]/[M18e]'s
# established tolerance-band convention) for two probabilistic species.
#
# Ground truth: pokeemerald_expansion src/pokemon.c ::
#   GetGenderFromSpeciesAndPersonality (L1847-1861) — the exact per-instance
#   resolution this project's _roll_gender ports; genderRatio ENCODING itself
#   is src/data/pokemon/species_info.h's PERCENT_FEMALE(percent) macro
#   (`min(254, (percent*255)/100)`) plus include/constants/pokemon.h's
#   MON_MALE=0/MON_FEMALE=0xFE/MON_GENDERLESS=0xFF sentinels.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_a_data_integrity()
	_test_section_b_instance_generation()

	var total := _pass + _fail
	print("m18_5d_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _make_species(gender_ratio: int) -> PokemonSpecies:
	var sp := PokemonSpecies.new()
	sp.species_name = "GenderTestMon"
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = 100
	sp.base_attack = 60
	sp.base_defense = 60
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = 60
	sp.gender_ratio = gender_ratio
	return sp


# ── Section A: data-integrity (PokemonRegistry, the real live data path) ────
# Five categories, each dex/ratio pair independently cross-checked against
# real source directly (not just internal JSON self-consistency) at Step 0:
#   Bulbasaur   dex=1   ratio=31  (PERCENT_FEMALE(12.5), skewed starter)
#   Rattata     dex=19  ratio=127 (PERCENT_FEMALE(50), the common 50/50 case)
#   Chansey     dex=113 ratio=254 (MON_FEMALE, always-female)
#   Ditto       dex=132 ratio=255 (MON_GENDERLESS)
#   Tyrogue     dex=236 ratio=0   (MON_MALE, always-male)

func _test_section_a_data_integrity() -> void:
	var bulbasaur: Dictionary = PokemonRegistry.get_species(1)
	_chk("A01 Bulbasaur (dex 1) gender_ratio == 31 (12.5%% female, skewed starter)",
			int(bulbasaur["gender_ratio"]) == 31)

	var rattata: Dictionary = PokemonRegistry.get_species(19)
	_chk("A02 Rattata (dex 19) gender_ratio == 127 (50/50)",
			int(rattata["gender_ratio"]) == 127)

	var chansey: Dictionary = PokemonRegistry.get_species(113)
	_chk("A03 Chansey (dex 113) gender_ratio == 254 (always female)",
			int(chansey["gender_ratio"]) == 254)

	var ditto: Dictionary = PokemonRegistry.get_species(132)
	_chk("A04 Ditto (dex 132) gender_ratio == 255 (genderless)",
			int(ditto["gender_ratio"]) == 255)

	var tyrogue: Dictionary = PokemonRegistry.get_species(236)
	_chk("A05 Tyrogue (dex 236) gender_ratio == 0 (always male)",
			int(tyrogue["gender_ratio"]) == 0)


# ── Section B: instance-generation (BattlePokemon.from_species -> gender) ───

func _test_section_b_instance_generation() -> void:
	# (i) Genderless: zero variance across n=500 -- no roll happens at all for
	# this sentinel value (see _roll_gender's early-return chain).
	var genderless_sp := _make_species(255)
	var n_locked := 500
	var genderless_ok := true
	for _i in range(n_locked):
		var bp := BattlePokemon.from_species(genderless_sp, 50)
		if bp.gender != BattlePokemon.GENDER_GENDERLESS:
			genderless_ok = false
	_chk("B01 genderless species (ratio=255) always produces GENDER_GENDERLESS, " +
			"zero variance across n=%d" % n_locked, genderless_ok)

	# (ii) Always-male: zero variance across n=500.
	var male_sp := _make_species(0)
	var male_ok := true
	for _i in range(n_locked):
		var bp := BattlePokemon.from_species(male_sp, 50)
		if bp.gender != BattlePokemon.GENDER_MALE:
			male_ok = false
	_chk("B02 always-male species (ratio=0) always produces GENDER_MALE, " +
			"zero variance across n=%d" % n_locked, male_ok)

	# (iii) Always-female: zero variance across n=500.
	var female_sp := _make_species(254)
	var female_ok := true
	for _i in range(n_locked):
		var bp := BattlePokemon.from_species(female_sp, 50)
		if bp.gender != BattlePokemon.GENDER_FEMALE:
			female_ok = false
	_chk("B03 always-female species (ratio=254) always produces GENDER_FEMALE, " +
			"zero variance across n=%d" % n_locked, female_ok)

	# (iv) Skewed (12.5% female, Bulbasaur's own ratio=31): statistical sample,
	# n=2000, wide margins matching [M17n-5]/[M18e]'s established
	# tolerance-band convention (many standard deviations wide, to avoid
	# flakiness -- expected SE at n=2000, p=0.125 is ~0.7pp, so a +-5pp band
	# is roughly 7 SDs wide).
	var skewed_sp := _make_species(31)
	var n_stat := 2000
	var skewed_female_count := 0
	for _i in range(n_stat):
		var bp := BattlePokemon.from_species(skewed_sp, 50)
		if bp.gender == BattlePokemon.GENDER_FEMALE:
			skewed_female_count += 1
	var skewed_rate: float = float(skewed_female_count) / n_stat
	_chk("B04 skewed species (ratio=31, expected ~12.5%% female) observed rate " +
			"within [7.5%%, 17.5%%] (n=%d, observed=%.3f)" % [n_stat, skewed_rate],
			skewed_rate > 0.075 and skewed_rate < 0.175)

	# (v) 50/50 (Rattata's own ratio=127): statistical sample, same n and margin
	# shape -- also serves as a discriminator confirming the `>` threshold
	# orientation isn't backwards (a reversed check would still pass a lenient
	# band, but this band is centered on the genuinely expected midpoint).
	var even_sp := _make_species(127)
	var even_female_count := 0
	for _i in range(n_stat):
		var bp := BattlePokemon.from_species(even_sp, 50)
		if bp.gender == BattlePokemon.GENDER_FEMALE:
			even_female_count += 1
	var even_rate: float = float(even_female_count) / n_stat
	_chk("B05 50/50 species (ratio=127, expected ~50%% female) observed rate " +
			"within [42.5%%, 57.5%%] (n=%d, observed=%.3f)" % [n_stat, even_rate],
			even_rate > 0.425 and even_rate < 0.575)

	# (vi) Discriminator: a plain from_species call for an ordinary species
	# defaults gender to something valid (not left at an uninitialized/garbage
	# value) -- sanity check that the field is always one of the three GENDER_*
	# constants.
	var plain_sp := _make_species(127)
	var plain_bp := BattlePokemon.from_species(plain_sp, 50)
	_chk("B06 discriminator: gender is always one of the three valid GENDER_* " +
			"constants", plain_bp.gender in [BattlePokemon.GENDER_MALE,
					BattlePokemon.GENDER_FEMALE, BattlePokemon.GENDER_GENDERLESS])
